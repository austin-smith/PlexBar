import PlexClientKit
import SwiftUI

@main
struct PlexBarApp: App {
    @State private var settingsStore: PlexSettingsStore
    @State private var connectionStore: PlexConnectionStore
    @State private var authStore: PlexAuthStore
    @State private var sessionStore: PlexSessionStore
    @State private var historyStore: PlexHistoryStore
    @State private var libraryStore: PlexLibraryStore
    @State private var browserStore: PlexBrowserStore
    @State private var playerCoordinator: PlexPlayerCoordinator
    @State private var mainNavigationStore: PlexMainNavigationStore
    @State private var serverPreviewStore: PlexServerPreviewStore
    @State private var downloadsStore: PlexDownloadsStore
    @State private var commandPaletteStore = PlexCommandPaletteStore()
    private let systemLifecycleObserver: PlexSystemLifecycleObserver
    private let userInteractionMonitor: PlexUserInteractionMonitor
    private let updateService: PlexUpdateService

    init() {
        let runtime = PlexAppRuntime.current()
        let settingsStore = runtime.settingsStore
        let resolver = runtime.connectionResolver
        let connectionStore = PlexConnectionStore(settings: settingsStore, resolver: resolver)
        let sessionStore = PlexSessionStore(
            connectionStore: connectionStore,
            client: runtime.apiClient,
            geoIPClient: runtime.geoIPClient,
            eventsClient: runtime.sessionEventsClient
        )
        let libraryStore = PlexLibraryStore(connectionStore: connectionStore, client: runtime.apiClient)
        let historyStore = PlexHistoryStore(
            connectionStore: connectionStore,
            libraryStore: libraryStore,
            client: runtime.apiClient
        )
        let serverPreviewStore = PlexServerPreviewStore(client: runtime.apiClient, resolver: resolver)
        let userInteractionStore = PlexUserInteractionStore()
        let browserStore = PlexBrowserStore(
            connectionStore: connectionStore,
            client: runtime.apiClient
        )
        let authStore = PlexAuthStore(
            settings: settingsStore,
            connectionStore: connectionStore,
            sessionStore: sessionStore,
            historyStore: historyStore,
            libraryStore: libraryStore,
            client: runtime.authClient,
            deviceIdentityStore: runtime.deviceIdentityStore
        )
        _settingsStore = State(initialValue: settingsStore)
        _connectionStore = State(initialValue: connectionStore)
        _sessionStore = State(initialValue: sessionStore)
        _historyStore = State(initialValue: historyStore)
        _libraryStore = State(initialValue: libraryStore)
        _browserStore = State(initialValue: browserStore)
        _playerCoordinator = State(initialValue: PlexPlayerCoordinator(
            userInteractionStore: userInteractionStore,
            bandwidthRegistry: runtime.playbackBandwidthRegistry
        ))
        _mainNavigationStore = State(initialValue: PlexMainNavigationStore())
        _serverPreviewStore = State(initialValue: serverPreviewStore)
        _authStore = State(initialValue: authStore)
        systemLifecycleObserver = PlexSystemLifecycleObserver(
            onWillSleep: { sessionStore.systemWillSleep() },
            onDidWake: { sessionStore.systemDidWake() }
        )
        userInteractionMonitor = PlexUserInteractionMonitor(store: userInteractionStore)
        updateService = PlexUpdateService()
        let downloadCreationStore = PlexDownloadCreationStore(
            authStore: authStore,
            connectionStore: connectionStore,
            libraryStore: libraryStore,
            browserStore: browserStore,
            transferCoordinator: runtime.downloadTransferCoordinator
        )
        _downloadsStore = State(initialValue: PlexDownloadsStore(
            authStore: authStore,
            connectionStore: connectionStore,
            browserStore: browserStore,
            client: runtime.apiClient,
            creationStore: downloadCreationStore,
            transferCoordinator: runtime.downloadTransferCoordinator,
            packageStore: runtime.downloadPackageStore,
            jobRegistry: runtime.downloadJobRegistry,
            playbackRegistry: runtime.offlinePlaybackRegistry,
            preparedAssetStore: runtime.downloadPreparedAssetStore
        ))
    }

    var body: some Scene {
        Window("PlexBar", id: PlexMainNavigationStore.windowID) {
            PlexMainWindowView(
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                authStore: authStore,
                sessionStore: sessionStore,
                historyStore: historyStore,
                libraryStore: libraryStore,
                browserStore: browserStore,
                playerCoordinator: playerCoordinator,
                navigationStore: mainNavigationStore,
                downloadsStore: downloadsStore,
                commandPaletteStore: commandPaletteStore
            )
            .frame(minWidth: 840, minHeight: 560)
            .task {
                await downloadsStore.start()
            }
            .environment(downloadsStore)
        }
        .defaultSize(width: 1_180, height: 760)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            PlexMainWindowCommands(paletteStore: commandPaletteStore)
            PlexPlaybackCommands(
                coordinator: playerCoordinator,
                settingsStore: settingsStore,
                isCommandPalettePresented: commandPaletteStore.isPresented
            )
        }

        Settings {
            SettingsView(
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                authStore: authStore,
                previewStore: serverPreviewStore,
                sessionStore: sessionStore,
                historyStore: historyStore,
                updateService: updateService
            )
        }
        .defaultSize(width: 520, height: 620)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContentView(
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                authStore: authStore,
                sessionStore: sessionStore,
                historyStore: historyStore,
                libraryStore: libraryStore,
                playerCoordinator: playerCoordinator,
                commandPaletteStore: commandPaletteStore
            )
        } label: {
            MenuBarLabelView(streamCount: sessionStore.activeStreamCount)
        }
        .menuBarExtraStyle(.window)
    }
}
