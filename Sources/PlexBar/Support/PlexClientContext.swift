import Foundation

struct PlexClientContext {
    let clientIdentifier: String

    var headers: [String: String] {
        [
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Product": AppConstants.appName,
            "X-Plex-Version": AppConstants.productVersion,
            "X-Plex-Platform": "macOS",
            "X-Plex-Platform-Version": platformVersion,
            "X-Plex-Device": "Mac",
            "X-Plex-Device-Name": "Mac (\(AppConstants.appName))",
            "X-Plex-Language": "en",
        ]
    }

    func authURL(for code: String) -> URL? {
        let headers = headers

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "clientID", value: headers["X-Plex-Client-Identifier"]),
            URLQueryItem(name: "context[device][product]", value: headers["X-Plex-Product"]),
            URLQueryItem(name: "context[device][version]", value: headers["X-Plex-Version"]),
            URLQueryItem(name: "context[device][platform]", value: headers["X-Plex-Platform"]),
            URLQueryItem(name: "context[device][platformVersion]", value: headers["X-Plex-Platform-Version"]),
            URLQueryItem(name: "context[device][device]", value: headers["X-Plex-Device"]),
            URLQueryItem(name: "context[device][deviceName]", value: headers["X-Plex-Device-Name"]),
            URLQueryItem(name: "code", value: code),
        ]

        guard let query = components.percentEncodedQuery else {
            return nil
        }

        return PlexRemoteService.authURL(query: query)
    }

    private var platformVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
