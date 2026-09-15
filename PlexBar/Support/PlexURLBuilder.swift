import PlexModels
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
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false),
              let pathComponents = URLComponents(string: path),
              pathComponents.scheme == nil,
              pathComponents.host == nil else {
            return nil
        }

        let basePath = components.path.trimmingSlashes()
        let relativePath = pathComponents.path.trimmingSlashes()
        let combinedPath = [basePath, relativePath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        components.path = "/" + combinedPath
        components.queryItems = pathComponents.queryItems
        return components.url
    }

    static func endpointURL(
        serverURL: URL,
        path: String,
        appendingPathComponent pathComponent: String
    ) -> URL? {
        endpointURL(
            serverURL: serverURL,
            path: path,
            appendingPathComponents: [pathComponent]
        )
    }

    static func endpointURL(
        serverURL: URL,
        path: String,
        appendingPathComponents appendedPathComponents: [String]
    ) -> URL? {
        guard var pathComponents = URLComponents(string: path),
              pathComponents.scheme == nil,
              pathComponents.host == nil,
              !appendedPathComponents.isEmpty else {
            return nil
        }

        let normalizedPathComponents = appendedPathComponents.compactMap { pathComponent -> String? in
            guard let pathComponent = pathComponent.nilIfBlank,
                  !pathComponent.contains("/") else {
                return nil
            }
            return pathComponent
        }
        guard normalizedPathComponents.count == appendedPathComponents.count else {
            return nil
        }

        let basePath = pathComponents.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        pathComponents.path = "/" + ([basePath] + normalizedPathComponents)
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        guard let appendedPath = pathComponents.string else {
            return nil
        }
        return endpointURL(serverURL: serverURL, path: appendedPath)
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
            URLQueryItem(name: "format", value: "jpeg")
        ]
        return components.url
    }

    static func transcodedPhotoURL(serverURL: URL, path: String?, width: Int, height: Int) -> URL? {
        guard let path = path?.nilIfBlank,
              width > 0,
              height > 0,
              var components = endpointURL(serverURL: serverURL, path: "/photo/:/transcode")
                .flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "url", value: path),
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "minSize", value: "0"),
            URLQueryItem(name: "upscale", value: "0"),
            URLQueryItem(name: "rotate", value: "1"),
            URLQueryItem(name: "quality", value: "-1"),
            URLQueryItem(name: "format", value: "jpeg"),
        ]
        return components.url
    }
}

extension String {
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
