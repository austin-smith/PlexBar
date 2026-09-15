import Foundation

@MainActor
struct PlexAppRuntime {
    enum Mode: Equatable {
        case live
        case mock
    }

    nonisolated private static let mockArgument = "--mock"
    private static let mockDefaultsSuiteName = "\(AppConstants.bundleIdentifier).mock"

    let settingsStore: PlexSettingsStore
    let authClient: PlexAuthClient
    let apiClient: PlexAPIClient
    let geoIPClient: PlexGeoIPClient
    let sessionEventsClient: PlexSessionEventsClient
    let connectionResolver: PlexConnectionResolver
    let deviceIdentityStore: any PlexDeviceIdentityProviding
    let downloadTransferCoordinator: PlexDownloadTransferCoordinator
    let downloadPackageStore: PlexDownloadPackageStore
    let downloadJobRegistry: PlexDownloadJobRegistry
    let offlinePlaybackRegistry: PlexOfflinePlaybackRegistry
    let downloadPreparedAssetStore: PlexDownloadPreparedAssetStore
    let playbackBandwidthRegistry: PlexPlaybackBandwidthRegistry

    static func current(processInfo: ProcessInfo = .processInfo) -> PlexAppRuntime {
        current(arguments: processInfo.arguments)
    }

    static func current(arguments: [String]) -> PlexAppRuntime {
        switch mode(arguments: arguments) {
        case .live:
            return liveRuntime()
        case .mock:
            return mockRuntime()
        }
    }

    nonisolated static func mode(arguments: [String]) -> Mode {
        #if DEBUG
        if arguments.contains(mockArgument) {
            return .mock
        }
        #else
        _ = arguments
        #endif

        return .live
    }

    nonisolated static func makeImageSession(arguments: [String]) -> URLSession {
        switch mode(arguments: arguments) {
        case .live:
            return .shared
        case .mock:
            return PlexDebugMockServer.makeSession()
        }
    }

    private static func liveRuntime() -> PlexAppRuntime {
        let settingsStore = PlexSettingsStore()
        let authClient = PlexAuthClient()
        let apiClient = PlexAPIClient()
        let geoIPClient = PlexGeoIPClient()
        let sessionEventsClient = PlexSessionEventsClient()
        let downloadPackageStore = PlexDownloadPackageStore()

        return PlexAppRuntime(
            settingsStore: settingsStore,
            authClient: authClient,
            apiClient: apiClient,
            geoIPClient: geoIPClient,
            sessionEventsClient: sessionEventsClient,
            connectionResolver: PlexConnectionResolver(client: apiClient),
            deviceIdentityStore: PlexKeychainDeviceIdentityStore(),
            downloadTransferCoordinator: .live(packageStore: downloadPackageStore),
            downloadPackageStore: downloadPackageStore,
            downloadJobRegistry: PlexDownloadJobRegistry(),
            offlinePlaybackRegistry: PlexOfflinePlaybackRegistry(),
            downloadPreparedAssetStore: PlexDownloadPreparedAssetStore(),
            playbackBandwidthRegistry: PlexPlaybackBandwidthRegistry()
        )
    }

    private static func mockRuntime() -> PlexAppRuntime {
        let settingsStore = mockSettingsStore()
        let session = PlexDebugMockServer.makeSession()
        let apiClient = PlexAPIClient(session: session)

        let downloadRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PlexBarMockDownloads-\(ProcessInfo.processInfo.globallyUniqueString)",
                isDirectory: true
            )
        let downloadPackageStore = PlexDownloadPackageStore(rootURL: downloadRootURL)
        return PlexAppRuntime(
            settingsStore: settingsStore,
            authClient: PlexAuthClient(session: session),
            apiClient: apiClient,
            geoIPClient: PlexGeoIPClient(session: session),
            sessionEventsClient: PlexDebugMockServer.makeEventsClient(),
            connectionResolver: PlexConnectionResolver(client: apiClient),
            deviceIdentityStore: PlexMemoryDeviceIdentityStore(),
            downloadTransferCoordinator: .inert(
                rootURL: downloadRootURL,
                packageStore: downloadPackageStore
            ),
            downloadPackageStore: downloadPackageStore,
            downloadJobRegistry: PlexDownloadJobRegistry(rootURL: downloadRootURL),
            offlinePlaybackRegistry: PlexOfflinePlaybackRegistry(rootURL: downloadRootURL),
            downloadPreparedAssetStore: PlexDownloadPreparedAssetStore(rootURL: downloadRootURL),
            playbackBandwidthRegistry: PlexPlaybackBandwidthRegistry(
                rootURL: downloadRootURL.appendingPathComponent("Playback", isDirectory: true)
            )
        )
    }

    private static func mockSettingsStore() -> PlexSettingsStore {
        let defaults = UserDefaults(suiteName: mockDefaultsSuiteName) ?? .standard
        defaults.removePersistentDomain(forName: mockDefaultsSuiteName)
        let credentials = PlexStoredCredentials(
            userToken: PlexDebugMockServer.mockUserToken,
            serverToken: PlexDebugMockServer.mockServer.accessToken
        )

        let settingsStore = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(credentials: credentials),
            initialCredentials: credentials
        )
        settingsStore.saveServerSelection(PlexDebugMockServer.mockServer)
        settingsStore.saveResolvedConnection(PlexDebugMockServer.mockResolvedConnection)
        return settingsStore
    }
}
