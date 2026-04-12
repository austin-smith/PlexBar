import Foundation

enum PlexURLBuilder {
    static func normalizeServerURL(_ rawValue: String) -> URL? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        let candidate = trimmedValue.contains("://") ? trimmedValue : "http://\(trimmedValue)"
        guard var components = URLComponents(string: candidate),
              components.host?.isEmpty == false else {
            return nil
        }

        if components.path == "/" {
            components.path = ""
        } else {
            components.path = components.path.trimmingTrailingSlash()
        }

        return components.url
    }

    static func endpointURL(serverURL: URL, path: String) -> URL? {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.path.trimmingSlashes()
        let relativePath = path.trimmingSlashes()
        let combinedPath = [basePath, relativePath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        components.path = "/" + combinedPath
        return components.url
    }

    static func mediaURL(serverURL: URL, path: String?) -> URL? {
        guard let path = path?.nilIfBlank else {
            return nil
        }

        return endpointURL(serverURL: serverURL, path: path)
    }

    static func transcodedArtworkURL(serverURL: URL, path: String?, width: Int, height: Int) -> URL? {
        guard let path = path?.nilIfBlank,
              var components = endpointURL(serverURL: serverURL, path: "/photo/:/transcode")
                .flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "url", value: path),
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "upscale", value: "1"),
            URLQueryItem(name: "format", value: "jpeg"),
        ]
        return components.url
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    fileprivate func trimmingSlashes() -> String {
        trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    fileprivate func trimmingTrailingSlash() -> String {
        guard hasSuffix("/") else {
            return self
        }

        return String(dropLast())
    }
}
