import Foundation
import PlexClientKit

enum TVAppConfiguration {
    static let bundleIdentifier: String = {
        guard let value = Bundle.main.bundleIdentifier else {
            preconditionFailure("The application bundle identifier is missing")
        }
        return value
    }()

    static let productVersion: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            preconditionFailure("The application version is missing")
        }
        return value
    }()
}

extension PlexClientContext {
    init(clientIdentifier: String) {
        self.init(
            clientIdentifier: clientIdentifier,
            product: "PlexBar",
            productVersion: TVAppConfiguration.productVersion,
            platform: "tvOS",
            device: "Apple TV",
            deviceName: "Apple TV (PlexBar)"
        )
    }
}
