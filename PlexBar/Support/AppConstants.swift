import Foundation

enum AppConstants {
    static let appName = "PlexBar"
    static let bundleIdentifier: String = {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            preconditionFailure("The application bundle identifier is missing")
        }
        return bundleIdentifier
    }()
    static let productVersion: String = {
        guard let productVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            preconditionFailure("The application version is missing")
        }
        return productVersion
    }()
    static let defaultConnectionRecheckIntervalSeconds = 900
    static let allowedConnectionRecheckIntervalSeconds = [0, 300, 900, 1_800, 3_600]
    static let defaultHistoryPollIntervalSeconds = 900
    static let allowedHistoryPollIntervalSeconds = [900, 3_600, 86_400]
}

enum KeychainAccounts {
    static let userToken = "plex-user-token"
    static let serverToken = "plex-server-token"
    static let jwtKeyID = "plex-jwt-key-id"
    static let jwtPrivateKey = "plex-jwt-private-key"
}
