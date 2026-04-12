import Foundation

enum AppConstants {
    static let appName = "PlexBar"
    static let bundleIdentifier = "com.crapshack.PlexBar"
    static let productVersion = "0.1.0"
    static let settingsWindowID = "settings"
    static let defaultPollInterval: Duration = .seconds(15)
}

enum KeychainAccounts {
    static let userToken = "plex-user-token"
    static let serverToken = "plex-server-token"
}
