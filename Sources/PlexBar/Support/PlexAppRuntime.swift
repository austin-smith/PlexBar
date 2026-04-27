import Foundation

@MainActor
struct PlexAppRuntime {
    enum Mode: Equatable {
        case live
        case mock
    }

    private static let mockArgument = "--mock"
    private static let mockDefaultsSuiteName = "\(AppConstants.bundleIdentifier).mock"
    private static let mockKeychainService = "\(AppConstants.bundleIdentifier).mock"

    let settingsStore: PlexSettingsStore
    let authClient: PlexAuthClient
    let apiClient: PlexAPIClient
    let geoIPClient: PlexGeoIPClient
    let sessionEventsClient: PlexSessionEventsClient
    let connectionResolver: PlexConnectionResolver

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

    static func mode(arguments: [String]) -> Mode {
        #if DEBUG
        if arguments.contains(mockArgument) {
            return .mock
        }
        #else
        _ = arguments
        #endif

        return .live
    }

    private static func liveRuntime() -> PlexAppRuntime {
        let settingsStore = PlexSettingsStore()
        let authClient = PlexAuthClient()
        let apiClient = PlexAPIClient()
        let geoIPClient = PlexGeoIPClient()
        let sessionEventsClient = PlexSessionEventsClient()

        return PlexAppRuntime(
            settingsStore: settingsStore,
            authClient: authClient,
            apiClient: apiClient,
            geoIPClient: geoIPClient,
            sessionEventsClient: sessionEventsClient,
            connectionResolver: PlexConnectionResolver(client: apiClient)
        )
    }

    private static func mockRuntime() -> PlexAppRuntime {
        let settingsStore = mockSettingsStore()
        let session = PlexDebugMockServer.makeSession()
        let apiClient = PlexAPIClient(session: session)

        return PlexAppRuntime(
            settingsStore: settingsStore,
            authClient: PlexAuthClient(session: session),
            apiClient: apiClient,
            geoIPClient: PlexGeoIPClient(session: session),
            sessionEventsClient: PlexDebugMockServer.makeEventsClient(),
            connectionResolver: PlexConnectionResolver(client: apiClient)
        )
    }

    private static func mockSettingsStore() -> PlexSettingsStore {
        let defaults = UserDefaults(suiteName: mockDefaultsSuiteName) ?? .standard
        defaults.removePersistentDomain(forName: mockDefaultsSuiteName)

        let settingsStore = PlexSettingsStore(
            defaults: defaults,
            keychain: KeychainStore(service: mockKeychainService)
        )
        settingsStore.saveAuthenticatedUserToken(PlexDebugMockServer.mockUserToken)
        settingsStore.saveServerSelection(PlexDebugMockServer.mockServer)
        settingsStore.saveResolvedConnection(PlexDebugMockServer.mockResolvedConnection)
        return settingsStore
    }
}
