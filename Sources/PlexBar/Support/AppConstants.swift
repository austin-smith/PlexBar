import Foundation

enum AppConstants {
    static let appName = "PlexBar"
    static let bundleIdentifier = "com.crapshack.PlexBar"
    static let productVersion = "0.3.0"
    static let settingsWindowID = "settings"
    static let defaultPollIntervalSeconds = 15
    static let minimumPollIntervalSeconds = 5
    static let maximumPollIntervalSeconds = 300
    static let defaultHistoryPollIntervalSeconds = 900
    static let allowedHistoryPollIntervalSeconds = [900, 3_600, 86_400]
}

enum KeychainAccounts {
    static let userToken = "plex-user-token"
    static let serverToken = "plex-server-token"
}
