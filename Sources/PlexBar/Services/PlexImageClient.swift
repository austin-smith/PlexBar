import AppKit
import CoreGraphics
import Foundation
import ImageIO

struct PlexFetchedImage {
    let image: NSImage
    let sourceURL: URL
}

struct PlexFetchedCGImage {
    let image: CGImage
    let sourceURL: URL
}

struct PlexImageClient {
    private let session: URLSession
    private let cache: PlexImageMemoryCache

    init(
        session: URLSession = .shared,
        cache: PlexImageMemoryCache = .shared
    ) {
        self.session = session
        self.cache = cache
    }

    func cachedImage(
        from urls: [URL],
        token: String?
    ) -> NSImage? {
        cachedImageResult(from: urls, token: token)?.image
    }

    func cachedImageResult(
        from urls: [URL],
        token: String?
    ) -> PlexFetchedImage? {
        for url in urls {
            if let image = cache.image(for: cacheKey(url: url, token: token)) {
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
        token: String?
    ) -> PlexFetchedCGImage? {
        for url in urls {
            if let image = cache.cgImage(for: cacheKey(url: url, token: token)) {
                return PlexFetchedCGImage(image: image, sourceURL: url)
            }
        }

        return nil
    }

    func fetchImage(
        from urls: [URL],
        token: String?,
        clientContext: PlexClientContext
    ) async -> NSImage? {
        await fetchImageResult(
            from: urls,
            token: token,
            clientContext: clientContext
        )?.image
    }

    func fetchImageResult(
        from urls: [URL],
        token: String?,
        clientContext: PlexClientContext
    ) async -> PlexFetchedImage? {
        let requestBuilder = PlexRequestBuilder(clientContext: clientContext)

        for url in urls {
            let cacheKey = cacheKey(url: url, token: token)
            if let image = cache.image(for: cacheKey) {
                return PlexFetchedImage(image: image, sourceURL: url)
            }

            let request = requestBuilder.request(
                url: url,
                accept: "image/*",
                token: token
            )

            let data: Data
            let response: URLResponse

            do {
                (data, response) = try await session.data(for: request)
            } catch {
                continue
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                continue
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                continue
            }

            guard let image = NSImage(data: data) else {
                continue
            }

            cache.insert(image, for: cacheKey)
            return PlexFetchedImage(image: image, sourceURL: url)
        }

        return nil
    }

    func fetchCGImageResult(
        from urls: [URL],
        token: String?,
        clientContext: PlexClientContext
    ) async -> PlexFetchedCGImage? {
        let requestBuilder = PlexRequestBuilder(clientContext: clientContext)

        for url in urls {
            let cacheKey = cacheKey(url: url, token: token)
            if let image = cache.cgImage(for: cacheKey) {
                return PlexFetchedCGImage(image: image, sourceURL: url)
            }

            let request = requestBuilder.request(
                url: url,
                accept: "image/*",
                token: token
            )

            let data: Data
            let response: URLResponse

            do {
                (data, response) = try await session.data(for: request)
            } catch {
                continue
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                continue
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                continue
            }

            guard let image = decodeCGImage(from: data) else {
                continue
            }

            cache.insert(image, for: cacheKey)
            return PlexFetchedCGImage(image: image, sourceURL: url)
        }

        return nil
    }

    private func cacheKey(url: URL, token: String?) -> String {
        if let token = token?.nilIfBlank {
            return "\(url.absoluteString)|\(token)"
        }

        return url.absoluteString
    }

    private func decodeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

final class PlexImageMemoryCache: @unchecked Sendable {
    static let shared = PlexImageMemoryCache()

    private let cache = NSCache<NSString, NSImage>()
    private let cgImageCache = NSCache<NSString, PlexCGImageBox>()
    private let paletteCache = NSCache<NSString, PlexArtworkPaletteBox>()

    private init() {
        cache.countLimit = 256
        cgImageCache.countLimit = 256
        paletteCache.countLimit = 256
    }

    func image(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: NSImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func cgImage(for key: String) -> CGImage? {
        cgImageCache.object(forKey: key as NSString)?.image
    }

    func insert(_ image: CGImage, for key: String) {
        cgImageCache.setObject(PlexCGImageBox(image), forKey: key as NSString)
    }

    func palette(for key: String) -> PlexArtworkPalette? {
        paletteCache.object(forKey: key as NSString)?.palette
    }

    func insert(_ palette: PlexArtworkPalette, for key: String) {
        paletteCache.setObject(PlexArtworkPaletteBox(palette), forKey: key as NSString)
    }
}

private final class PlexArtworkPaletteBox {
    let palette: PlexArtworkPalette

    init(_ palette: PlexArtworkPalette) {
        self.palette = palette
    }
}

private final class PlexCGImageBox {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}
