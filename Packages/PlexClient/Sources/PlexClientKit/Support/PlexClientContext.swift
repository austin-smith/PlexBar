import Foundation

public struct PlexClientContext: Hashable, Sendable {
    public static let pmsAPIVersion = "1.0.0"

    public let clientIdentifier: String
    public let product: String
    public let productVersion: String
    public let platform: String
    public let device: String
    public let deviceName: String

    public init(
        clientIdentifier: String,
        product: String,
        productVersion: String,
        platform: String,
        device: String,
        deviceName: String
    ) {
        self.clientIdentifier = clientIdentifier
        self.product = product
        self.productVersion = productVersion
        self.platform = platform
        self.device = device
        self.deviceName = deviceName
    }

    public var headers: [String: String] {
        [
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Product": product,
            "X-Plex-Version": productVersion,
            "X-Plex-Platform": platform,
            "X-Plex-Platform-Version": platformVersion,
            "X-Plex-Device": device,
            "X-Plex-Device-Name": deviceName,
            "X-Plex-Language": "en",
        ]
    }

    public func authURL(for code: String) -> URL? {
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
