import AppKit
import Foundation

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
        for url in urls {
            if let image = cache.image(for: cacheKey(url: url, token: token)) {
                return image
            }
        }

        return nil
    }

    func fetchImage(
        from urls: [URL],
        token: String?,
        clientContext: PlexClientContext
    ) async -> NSImage? {
        let requestBuilder = PlexRequestBuilder(clientContext: clientContext)

        for url in urls {
            let cacheKey = cacheKey(url: url, token: token)
            if let image = cache.image(for: cacheKey) {
                return image
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
            return image
        }

        return nil
    }

    private func cacheKey(url: URL, token: String?) -> String {
        if let token = token?.nilIfBlank {
            return "\(url.absoluteString)|\(token)"
        }

        return url.absoluteString
    }
}

final class PlexImageMemoryCache: @unchecked Sendable {
    static let shared = PlexImageMemoryCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 256
    }

    func image(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: NSImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
