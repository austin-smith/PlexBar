import PlexModels
import AppKit
import CoreGraphics
import Foundation

struct PlexFetchedImage {
    let image: NSImage
    let sourceURL: URL
}

struct PlexFetchedCGImage {
    let image: CGImage
    let sourceURL: URL
}

struct PlexImageClient: Sendable {
    // Share one transport for image loaders created throughout the app. Mock
    // images must remain loadable after cache eviction and at any requested size.
    static let defaultSession: URLSession = {
        #if DEBUG && os(macOS)
        PlexAppRuntime.makeImageSession(arguments: ProcessInfo.processInfo.arguments)
        #else
        URLSession.shared
        #endif
    }()

    private let session: URLSession
    private let cache: PlexImageMemoryCache
    private let requestCoordinator: PlexImageRequestCoordinator

    init(
        session: URLSession = PlexImageClient.defaultSession,
        cache: PlexImageMemoryCache = .shared,
        requestCoordinator: PlexImageRequestCoordinator = .shared
    ) {
        self.session = session
        self.cache = cache
        self.requestCoordinator = requestCoordinator
    }

    func cachedImage(
        from urls: [URL],
        token: String?,
        maximumPixelSize: Int? = nil
    ) -> NSImage? {
        cachedImageResult(
            from: urls,
            token: token,
            maximumPixelSize: maximumPixelSize
        )?.image
    }

    func cachedImageResult(
        from urls: [URL],
        token: String?,
        maximumPixelSize: Int? = nil
    ) -> PlexFetchedImage? {
        for url in urls {
            if let image = cache.image(for: cacheKey(
                url: url,
                token: token,
                maximumPixelSize: maximumPixelSize
            )) {
                return PlexFetchedImage(image: image, sourceURL: url)
            }
        }

        return nil
    }

    func cachedPalette(for url: URL, token: String?) -> PlexArtworkPalette? {
        cache.palette(for: cacheKey(url: url, token: token))
    }

    func cachePalette(_ palette: PlexArtworkPalette, for url: URL, token: String?) {
        cache.insert(palette, for: cacheKey(url: url, token: token))
    }

    func cachedCGImageResult(
        from urls: [URL],
        token: String?,
        maximumPixelSize: Int? = nil
    ) -> PlexFetchedCGImage? {
        for url in urls {
            if let image = cache.cgImage(for: cacheKey(
                url: url,
                token: token,
                maximumPixelSize: maximumPixelSize
            )) {
                return PlexFetchedCGImage(image: image, sourceURL: url)
            }
        }

        return nil
    }

    func fetchImage(
        from urls: [URL],
        token: String?,
        clientContext: PlexClientContext,
        maximumPixelSize: Int? = nil
    ) async -> NSImage? {
        await fetchImageResult(
            from: urls,
            token: token,
            clientContext: clientContext,
            maximumPixelSize: maximumPixelSize
        )?.image
    }

    func fetchImageResult(
        from urls: [URL],
        token: String?,
        clientContext: PlexClientContext,
        maximumPixelSize: Int? = nil
    ) async -> PlexFetchedImage? {
        guard let result = await fetchCGImageResult(
            from: urls,
            token: token,
            clientContext: clientContext,
            maximumPixelSize: maximumPixelSize
        ) else {
            return nil
        }

        return PlexFetchedImage(
            image: NSImage(
                cgImage: result.image,
                size: NSSize(width: result.image.width, height: result.image.height)
            ),
            sourceURL: result.sourceURL
        )
    }

    func fetchCGImageResult(
        from urls: [URL],
        token: String?,
        clientContext: PlexClientContext,
        maximumPixelSize: Int? = nil
    ) async -> PlexFetchedCGImage? {
        let requestBuilder = PlexRequestBuilder(clientContext: clientContext)

        for url in urls {
            let cacheKey = cacheKey(
                url: url,
                token: token,
                maximumPixelSize: maximumPixelSize
            )
            if let image = cache.cgImage(for: cacheKey) {
                return PlexFetchedCGImage(image: image, sourceURL: url)
            }

            let request: URLRequest
            if token?.nilIfBlank != nil {
                request = requestBuilder.request(
                    url: url,
                    accept: "image/*",
                    token: token
                )
            } else {
                var publicRequest = URLRequest(url: url)
                publicRequest.setValue("image/*", forHTTPHeaderField: "Accept")
                request = publicRequest
            }

            guard let image = await requestCoordinator.image(for: cacheKey, operation: {
                let data: Data
                do {
                    if url.isFileURL {
                        data = try await Self.localImageData(at: url)
                    } else {
                        let (responseData, response) = try await session.data(for: request)
                        guard let httpResponse = response as? HTTPURLResponse,
                              (200..<300).contains(httpResponse.statusCode) else {
                            return nil
                        }
                        data = responseData
                    }
                } catch {
                    return nil
                }

                guard let imageBox = await PlexImageDecoder.decodeCGImage(
                        from: data,
                        maximumPixelSize: maximumPixelSize
                      ) else {
                    return nil
                }

                cache.insert(imageBox.image, for: cacheKey)
                return imageBox
            }) else {
                continue
            }

            return PlexFetchedCGImage(image: image, sourceURL: url)
        }

        return nil
    }

    @concurrent
    private static func localImageData(at url: URL) async throws -> Data {
        try Data(contentsOf: url)
    }

    private func cacheKey(
        url: URL,
        token: String?,
        maximumPixelSize: Int? = nil
    ) -> String {
        let sizeSuffix = maximumPixelSize.map { "|pixels=\($0)" } ?? ""
        if let token = token?.nilIfBlank {
            return "\(url.absoluteString)|\(token)\(sizeSuffix)"
        }

        return url.absoluteString + sizeSuffix
    }

}

final class PlexImageMemoryCache: @unchecked Sendable {
    static let shared = PlexImageMemoryCache()

    private let lock = NSLock()
    private let cgImageCache = NSCache<NSString, PlexCGImageBox>()
    private let paletteCache = NSCache<NSString, PlexArtworkPaletteBox>()
    private let imageCountLimit: Int
    private let imageCostLimit: Int
    private let paletteCountLimit: Int
    private var imageCosts: [String: Int] = [:]
    private var imageLRU: [String] = []
    private var imageCost = 0
    private var paletteLRU: [String] = []

    init(
        imageCountLimit: Int = 256,
        imageCostLimit: Int = 96 * 1_024 * 1_024,
        paletteCountLimit: Int = 512
    ) {
        self.imageCountLimit = max(0, imageCountLimit)
        self.imageCostLimit = max(0, imageCostLimit)
        self.paletteCountLimit = max(0, paletteCountLimit)
        cgImageCache.countLimit = self.imageCountLimit
        cgImageCache.totalCostLimit = self.imageCostLimit
        paletteCache.countLimit = self.paletteCountLimit
    }

    func image(for key: String) -> NSImage? {
        guard let image = cgImage(for: key) else {
            return nil
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    func insert(_ image: NSImage, for key: String) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }
        insert(cgImage, for: key)
    }

    func cgImage(for key: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }

        guard let image = cgImageCache.object(forKey: key as NSString)?.image else {
            removeImageMetadata(for: key)
            return nil
        }
        touch(key, in: &imageLRU)
        return image
    }

    func insert(_ image: CGImage, for key: String) {
        let cost = image.bytesPerRow * image.height
        lock.lock()
        defer { lock.unlock() }

        pruneEvictedImages()
        removeImageMetadata(for: key)
        cgImageCache.removeObject(forKey: key as NSString)

        guard imageCountLimit > 0,
              imageCostLimit > 0,
              cost <= imageCostLimit else {
            return
        }

        while imageLRU.count >= imageCountLimit || imageCost + cost > imageCostLimit {
            guard let evictedKey = imageLRU.first else {
                break
            }
            cgImageCache.removeObject(forKey: evictedKey as NSString)
            removeImageMetadata(for: evictedKey)
        }

        cgImageCache.setObject(PlexCGImageBox(image), forKey: key as NSString, cost: cost)
        imageCosts[key] = cost
        imageLRU.append(key)
        imageCost += cost
    }

    func palette(for key: String) -> PlexArtworkPalette? {
        lock.lock()
        defer { lock.unlock() }

        guard let palette = paletteCache.object(forKey: key as NSString)?.palette else {
            paletteLRU.removeAll { $0 == key }
            return nil
        }
        touch(key, in: &paletteLRU)
        return palette
    }

    func insert(_ palette: PlexArtworkPalette, for key: String) {
        lock.lock()
        defer { lock.unlock() }

        pruneEvictedPalettes()
        paletteCache.removeObject(forKey: key as NSString)
        paletteLRU.removeAll { $0 == key }
        guard paletteCountLimit > 0 else {
            return
        }

        while paletteLRU.count >= paletteCountLimit, let evictedKey = paletteLRU.first {
            paletteCache.removeObject(forKey: evictedKey as NSString)
            paletteLRU.removeFirst()
        }

        paletteCache.setObject(PlexArtworkPaletteBox(palette), forKey: key as NSString)
        paletteLRU.append(key)
    }

    private func pruneEvictedImages() {
        for key in imageLRU where cgImageCache.object(forKey: key as NSString) == nil {
            if let cost = imageCosts.removeValue(forKey: key) {
                imageCost -= cost
            }
        }
        imageLRU.removeAll { imageCosts[$0] == nil }
    }

    private func pruneEvictedPalettes() {
        paletteLRU.removeAll { paletteCache.object(forKey: $0 as NSString) == nil }
    }

    private func removeImageMetadata(for key: String) {
        if let cost = imageCosts.removeValue(forKey: key) {
            imageCost -= cost
        }
        imageLRU.removeAll { $0 == key }
    }

    private func touch(_ key: String, in keys: inout [String]) {
        keys.removeAll { $0 == key }
        keys.append(key)
    }
}

actor PlexImageRequestCoordinator {
    static let shared = PlexImageRequestCoordinator()

    private var inFlight: [String: Task<PlexCGImageBox?, Never>] = [:]

    func image(
        for key: String,
        operation: @escaping @Sendable () async -> PlexCGImageBox?
    ) async -> CGImage? {
        if let existingTask = inFlight[key] {
            return await existingTask.value?.image
        }

        let task = Task(operation: operation)
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result?.image
    }
}

private final class PlexArtworkPaletteBox {
    let palette: PlexArtworkPalette

    init(_ palette: PlexArtworkPalette) {
        self.palette = palette
    }
}
