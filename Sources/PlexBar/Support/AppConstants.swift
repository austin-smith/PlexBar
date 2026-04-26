import Foundation

enum AppConstants {
    static let appName = "PlexBar"
    static let bundleIdentifier = "com.crapshack.PlexBar"
    static let productVersion = "0.6.0"
    static let defaultConnectionRecheckIntervalSeconds = 900
    static let allowedConnectionRecheckIntervalSeconds = [0, 300, 900, 1_800, 3_600]
    static let defaultHistoryPollIntervalSeconds = 900
    static let allowedHistoryPollIntervalSeconds = [900, 3_600, 86_400]
}

enum KeychainAccounts {
    static let userToken = "plex-user-token"
    static let serverToken = "plex-server-token"
}
