import Foundation

struct PlexImageRequest: Equatable, Sendable {
    let url: URL
    let token: String

    init?(path: String?, serverURL: URL?, serverToken: String) {
        guard let path = path?.nilIfBlank,
              let serverURL else {
            return nil
        }

        if let absoluteURL = URL(string: path), absoluteURL.scheme != nil {
            guard ["http", "https"].contains(absoluteURL.scheme?.lowercased() ?? ""),
                  absoluteURL.host?.nilIfBlank != nil else {
                return nil
            }
            url = absoluteURL
            token = Self.hasSameOrigin(absoluteURL, serverURL) ? serverToken : ""
        } else {
            guard let relativeURL = PlexURLBuilder.mediaURL(serverURL: serverURL, path: path) else {
                return nil
            }
            url = relativeURL
            token = serverToken
        }
    }

    static func hasSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }
}
