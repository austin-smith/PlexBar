import Foundation

enum PlexRemoteService {
    static let apiBaseURL = URL(string: "https://plex.tv")!
    static let authAppBaseURL = URL(string: "https://app.plex.tv")!
    static let websiteURL = URL(string: "https://www.plex.tv/")!

    static func apiURL(path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    static func authURL(query: String) -> URL {
        URL(string: authAppBaseURL.absoluteString + "/auth/#!?\(query)")!
    }

    static func isPlexHosted(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "plex.tv" || host.hasSuffix(".plex.tv")
    }
}
