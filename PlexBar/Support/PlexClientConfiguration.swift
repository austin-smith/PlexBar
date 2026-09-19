import PlexClientKit

extension PlexClientContext {
    init(clientIdentifier: String) {
        self.init(
            clientIdentifier: clientIdentifier,
            product: AppConstants.appName,
            productVersion: AppConstants.productVersion,
            platform: "macOS",
            device: "Mac",
            deviceName: "Mac (\(AppConstants.appName))"
        )
    }
}
