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

    static func authenticatedURL(serverURL: URL, path: String?, token: String) -> URL? {
        guard let path = path?.nilIfBlank,
              var components = endpointURL(serverURL: serverURL, path: path)
                .flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            return nil
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "X-Plex-Token" }
        queryItems.append(URLQueryItem(name: "X-Plex-Token", value: token))
        components.queryItems = queryItems
        return components.url
    }

    static func transcodedArtworkURL(serverURL: URL, path: String?, token: String, width: Int, height: Int) -> URL? {
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
            URLQueryItem(name: "X-Plex-Token", value: token),
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
