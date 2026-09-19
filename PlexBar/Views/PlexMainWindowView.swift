import PlexClientKit
import PlexModels
import SwiftUI

struct PlexMainWindowView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var authStore: PlexAuthStore
    @Bindable var sessionStore: PlexSessionStore
    @Bindable var historyStore: PlexHistoryStore
    @Bindable var libraryStore: PlexLibraryStore
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    @Bindable var navigationStore: PlexMainNavigationStore
    @Bindable var downloadsStore: PlexDownloadsStore
    @State private var libraryPresentationStore = PlexLibraryPresentationStore()
    @State private var selectionBeforeGlobalSearch: PlexMainSection?
    @FocusState private var isGlobalSearchFocused: Bool

    var body: some View {
        ZStack {
            if let presentation = playerCoordinator.presentation {
                PlexPlayerView(
                    presentation: presentation,
                    browserStore: browserStore,
                    settingsStore: settingsStore,
                    coordinator: playerCoordinator,
                    downloadsStore: downloadsStore
                )
                .id(presentation.id)
                .transition(PlexMotion.surfaceTransition)
            } else {
                NavigationSplitView {
                    List(selection: sidebarSelection) {
                        Section {
                            navigationRow(.home)
                        }

                        if !libraryStore.libraries.isEmpty {
                            Section("Libraries") {
                                ForEach(libraryStore.libraries) { library in
                                    Label(library.title, systemImage: library.type.symbolName)
                                        .tag(PlexMainSection.library(library.id))
                                }
                            }
                        }

                        Section("Media") {
                            navigationRow(.downloads)
                            navigationRow(.collections)
                            navigationRow(.playlists)
                        }

                        Section("Server") {
                            navigationRow(.activity, badge: sessionStore.activeStreamCount)
                            navigationRow(.history)
                            navigationRow(.users)
                        }
                    }
                    .modifier(PlexActivityVisibility(store: sessionStore))
                    .navigationTitle("PlexBar")
                    .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
                    .searchable(
                        text: globalSearchText,
                        placement: .sidebar,
                        prompt: "Search"
                    )
                    .searchFocused($isGlobalSearchFocused)
                } detail: {
                    ZStack {
                        detail
                            .id(detailPresentationIdentity)
                            .transition(PlexMotion.surfaceTransition)
                    }
                    .animation(
                        PlexMotion.surfaceAnimation(reduceMotion: accessibilityReduceMotion),
                        value: detailPresentationIdentity
                    )
                }
                .navigationSplitViewStyle(.balanced)
                .transition(PlexMotion.surfaceTransition)
            }
        }
        .animation(
            PlexMotion.surfaceAnimation(reduceMotion: accessibilityReduceMotion),
            value: playerCoordinator.presentation?.id
        )
        .focusedSceneValue(
            \.plexSearchCommand,
            PlexFocusedCommandAction(
                title: "Search All Libraries",
                isEnabled: playerCoordinator.presentation == nil
                    && settingsStore.hasValidConfiguration
            ) {
                isGlobalSearchFocused = true
            }
        )
        .focusedSceneValue(
            \.plexRefreshCommand,
            PlexFocusedCommandAction(
                title: "Refresh All",
                isEnabled: playerCoordinator.presentation == nil
                    && settingsStore.hasValidConfiguration,
                perform: refreshAllData
            )
        )
        .task {
            await start()
        }
        .onChange(of: libraryStore.libraries.map(\.id), initial: true) { _, libraryIDs in
            libraryPresentationStore.synchronize(libraryIDs: libraryIDs)
        }
        .onChange(of: connectionStore.accountCacheScope) { _, _ in
            resetStateForAccountChange()
            Task {
                await downloadsStore.resumePendingJobs()
                await downloadsStore.synchronizeOfflineProgress()
            }
        }
        .onChange(of: browserStore.globalSearchStore.normalizedQuery) { oldQuery, newQuery in
            if oldQuery.isEmpty, !newQuery.isEmpty {
                selectionBeforeGlobalSearch = navigationStore.selection
                navigationStore.selection = nil
            } else if !oldQuery.isEmpty, newQuery.isEmpty {
                browserStore.globalSearchStore.reset()
                if navigationStore.selection == nil {
                    navigationStore.selection = selectionBeforeGlobalSearch ?? .home
                }
                selectionBeforeGlobalSearch = nil
            }
        }
        .onChange(of: browserStore.globalSearchStore.navigationPath) { _, navigationPath in
            if !navigationPath.isEmpty {
                isGlobalSearchFocused = false
            }
        }
        .toolbar {
            if playerCoordinator.presentation == nil, !usesDestinationToolbar {
                ToolbarItem {
                    Button("Refresh", systemImage: "arrow.clockwise", action: refreshAllData)
                        .disabled(!settingsStore.hasValidConfiguration)
                }
            }
        }
    }

    private func navigationRow(_ section: PlexMainSection, badge: Int = 0) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .badge(badge)
            .tag(section)
    }

    private var sidebarSelection: Binding<PlexMainSection?> {
        Binding(
            get: { navigationStore.selection },
            set: { selection in
                navigationStore.selection = selection
                if selection != nil {
                    selectionBeforeGlobalSearch = nil
                }
                dismissGlobalSearch()
            }
        )
    }

    private var globalSearchText: Binding<String> {
        Binding(
            get: { browserStore.globalSearchStore.text },
            set: { browserStore.globalSearchStore.text = $0 }
        )
    }

    private var presentsGlobalSearch: Bool {
        settingsStore.hasValidConfiguration
            && !browserStore.globalSearchStore.normalizedQuery.isEmpty
    }

    private var detailPresentationIdentity: DetailPresentationIdentity {
        if presentsGlobalSearch {
            return .globalSearch
        }
        return .section(navigationStore.selection ?? .home)
    }

    @ViewBuilder
    private var detail: some View {
        if presentsGlobalSearch {
            PlexGlobalSearchNavigationHost(
                searchStore: browserStore.globalSearchStore,
                browserStore: browserStore,
                historyStore: historyStore,
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                playerCoordinator: playerCoordinator
            )
        } else if navigationStore.selection == .downloads {
            PlexDownloadsView(
                downloadsStore: downloadsStore,
                playerCoordinator: playerCoordinator
            )
        } else if !settingsStore.hasLoadedCredentials {
            if let errorMessage = settingsStore.credentialLoadingErrorMessage,
               !settingsStore.isLoadingCredentials {
                ContentUnavailableView {
                    Label("Couldn’t Access Keychain", systemImage: "key.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") {
                        Task { await start() }
                    }
                }
            } else {
                ProgressView("Loading Account…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if !settingsStore.hasAuthenticatedAccount {
            PlexAccountRequiredView(
                settingsStore: settingsStore,
                authStore: authStore
            )
        } else if !settingsStore.hasValidConfiguration {
            PlexServerRequiredView(authStore: authStore)
        } else {
            switch navigationStore.selection ?? .home {
            case .home:
                PlexMediaNavigationStack(
                    path: $navigationStore.homeNavigationPath,
                    browserStore: browserStore,
                    historyStore: historyStore,
                    settingsStore: settingsStore,
                    connectionStore: connectionStore,
                    playerCoordinator: playerCoordinator
                ) {
                    PlexHomeView(
                        browserStore: browserStore,
                        settingsStore: settingsStore,
                        connectionStore: connectionStore,
                        playerCoordinator: playerCoordinator
                    )
                }
            case .downloads:
                PlexDownloadsView(
                    downloadsStore: downloadsStore,
                    playerCoordinator: playerCoordinator
                )
            case .library(let libraryID):
                if let library = libraryStore.libraries.first(where: { $0.id == libraryID }),
                   let presentationState = libraryPresentationStore.state(for: libraryID) {
                    PlexLibraryNavigationHost(
                        library: library,
                        presentationState: presentationState,
                        browserStore: browserStore,
                        historyStore: historyStore,
                        settingsStore: settingsStore,
                        connectionStore: connectionStore,
                        playerCoordinator: playerCoordinator
                    )
                } else {
                    ContentUnavailableView("Library Unavailable", systemImage: "books.vertical")
                }
            case .collections:
                PlexMediaNavigationStack(
                    path: $navigationStore.collectionsNavigationPath,
                    browserStore: browserStore,
                    historyStore: historyStore,
                    settingsStore: settingsStore,
                    connectionStore: connectionStore,
                    playerCoordinator: playerCoordinator
                ) {
                    PlexCollectionsView(
                        libraries: libraryStore.libraries,
                        browserStore: browserStore,
                        settingsStore: settingsStore,
                        connectionStore: connectionStore,
                        playerCoordinator: playerCoordinator
                    )
                }
            case .playlists:
                PlexMediaNavigationStack(
                    path: $navigationStore.playlistsNavigationPath,
                    browserStore: browserStore,
                    historyStore: historyStore,
                    settingsStore: settingsStore,
                    connectionStore: connectionStore,
                    playerCoordinator: playerCoordinator
                ) {
                    PlexPlaylistsView(
                        browserStore: browserStore,
                        settingsStore: settingsStore,
                        connectionStore: connectionStore,
                        playerCoordinator: playerCoordinator
                    )
                }
            case .activity:
                PlexActivityView(
                    settingsStore: settingsStore,
                    connectionStore: connectionStore,
                    sessionStore: sessionStore
                )
            case .history:
                PlexMediaNavigationStack(
                    path: $navigationStore.historyNavigationPath,
                    browserStore: browserStore,
                    historyStore: historyStore,
                    settingsStore: settingsStore,
                    connectionStore: connectionStore,
                    playerCoordinator: playerCoordinator
                ) {
                    ScrollView {
                        HistoryDashboardView(
                            settingsStore: settingsStore,
                            serverURL: connectionStore.resolvedServerURL,
                            historyStore: historyStore,
                            allowsMediaNavigation: true
                        )
                        .scenePadding()
                    }
                    .navigationTitle("History")
                    .focusedSceneValue(
                        \.plexRefreshCommand,
                        PlexFocusedCommandAction(
                            title: "Refresh History",
                            isEnabled: !historyStore.isLoading,
                            perform: historyStore.refreshNow
                        )
                    )
                    .toolbar {
                        ToolbarItem {
                            Button("Refresh History", systemImage: "arrow.clockwise", action: historyStore.refreshNow)
                                .disabled(historyStore.isLoading)
                        }
                    }
                }
            case .users:
                ScrollView {
                    UsersDashboardView(
                        settingsStore: settingsStore,
                        serverURL: connectionStore.resolvedServerURL,
                        historyStore: historyStore
                    )
                    .scenePadding()
                }
                .navigationTitle("Users")
            }
        }
    }

    private func refreshAllData() {
        guard settingsStore.hasLoadedCredentials else {
            return
        }
        sessionStore.refreshNow()
        historyStore.refreshNow()
        libraryStore.refreshNow()
    }

    private func start() async {
        await settingsStore.loadCredentials()
        guard settingsStore.hasLoadedCredentials else {
            return
        }
        await authStore.credentialsDidLoad()
        await downloadsStore.resumePendingJobs()
        await downloadsStore.synchronizeOfflineProgress()
        refreshAllData()
        await browserStore.loadHomeHubs()
    }

    private var usesDestinationToolbar: Bool {
        if presentsGlobalSearch {
            return true
        }
        switch navigationStore.selection {
        case .home, .downloads, .library, .collections, .playlists, .history:
            return true
        default:
            return false
        }
    }

    private func dismissGlobalSearch() {
        guard isGlobalSearchFocused
                || !browserStore.globalSearchStore.normalizedQuery.isEmpty
                || !browserStore.globalSearchStore.navigationPath.isEmpty else {
            return
        }
        isGlobalSearchFocused = false
        browserStore.globalSearchStore.reset()
    }

    private func resetStateForAccountChange() {
        playerCoordinator.clear()
        navigationStore.resetForServerChange()
        browserStore.resetServerScopedState()
        libraryStore.resetServerScopedState()
        historyStore.resetServerScopedState()
        sessionStore.didChangeConfiguration()
        libraryPresentationStore.removeAll()
    }
}

private enum DetailPresentationIdentity: Hashable {
    case globalSearch
    case section(PlexMainSection)
}

private struct PlexGlobalSearchNavigationHost: View {
    @Bindable var searchStore: PlexGlobalSearchStore
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var historyStore: PlexHistoryStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator

    var body: some View {
        PlexMediaNavigationStack(
            path: $searchStore.navigationPath,
            browserStore: browserStore,
            historyStore: historyStore,
            settingsStore: settingsStore,
            connectionStore: connectionStore,
            playerCoordinator: playerCoordinator
        ) {
            PlexGlobalSearchView(
                searchStore: searchStore,
                browserStore: browserStore,
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                playerCoordinator: playerCoordinator
            )
        }
    }
}

private struct PlexLibraryNavigationHost: View {
    let library: PlexLibrary
    @Bindable var presentationState: PlexLibraryPresentationState
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var historyStore: PlexHistoryStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator

    var body: some View {
        PlexMediaNavigationStack(
            path: $presentationState.navigationPath,
            browserStore: browserStore,
            historyStore: historyStore,
            settingsStore: settingsStore,
            connectionStore: connectionStore,
            playerCoordinator: playerCoordinator
        ) {
            PlexLibraryBrowserView(
                library: library,
                searchStore: presentationState.searchStore,
                scrollPosition: $presentationState.scrollPosition,
                browserStore: browserStore,
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                playerCoordinator: playerCoordinator
            )
        }
    }
}

private struct PlexMediaNavigationStack<Root: View>: View {
    @Binding var path: [PlexNavigationRoute]
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var historyStore: PlexHistoryStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    @ViewBuilder let root: Root

    init(
        path: Binding<[PlexNavigationRoute]>,
        browserStore: PlexBrowserStore,
        historyStore: PlexHistoryStore,
        settingsStore: PlexSettingsStore,
        connectionStore: PlexConnectionStore,
        playerCoordinator: PlexPlayerCoordinator,
        @ViewBuilder root: () -> Root
    ) {
        _path = path
        self.browserStore = browserStore
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        self.connectionStore = connectionStore
        self.playerCoordinator = playerCoordinator
        self.root = root()
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: PlexNavigationRoute.self) { route in
                    switch route {
                    case .media(let mediaRoute):
                        PlexResolvedMediaDestinationView(
                            route: mediaRoute,
                            browserStore: browserStore,
                            historyStore: historyStore,
                            settingsStore: settingsStore,
                            connectionStore: connectionStore,
                            playerCoordinator: playerCoordinator
                        )
                    case .person(let personRoute):
                        PlexPersonDetailsView(
                            route: personRoute,
                            browserStore: browserStore,
                            settingsStore: settingsStore,
                            connectionStore: connectionStore,
                            playerCoordinator: playerCoordinator
                        )
                    case .homeHub(let hubRoute):
                        if let hub = browserStore.homeHub(for: hubRoute) {
                            PlexHomeHubItemsView(
                                hub: hub,
                                browserStore: browserStore,
                                settingsStore: settingsStore,
                                connectionStore: connectionStore,
                                playerCoordinator: playerCoordinator
                            )
                        } else {
                            ContentUnavailableView("Home Section Unavailable", systemImage: "rectangle.stack")
                        }
                    case .searchHub(let hubRoute):
                        if let hub = browserStore.globalSearchStore.hub(for: hubRoute) {
                            PlexSearchHubItemsView(
                                hub: hub,
                                searchStore: browserStore.globalSearchStore,
                                browserStore: browserStore,
                                settingsStore: settingsStore,
                                connectionStore: connectionStore,
                                playerCoordinator: playerCoordinator
                            )
                        } else {
                            ContentUnavailableView("Search Section Unavailable", systemImage: "rectangle.stack")
                        }
                    case .relatedHub(let hubRoute):
                        if let hub = browserStore.relatedHub(for: hubRoute) {
                            PlexRelatedHubItemsView(
                                route: hubRoute,
                                hub: hub,
                                browserStore: browserStore,
                                settingsStore: settingsStore,
                                connectionStore: connectionStore,
                                playerCoordinator: playerCoordinator
                            )
                        } else {
                            ContentUnavailableView("Related Section Unavailable", systemImage: "rectangle.stack")
                        }
                    }
                }
        }
    }
}

private struct PlexResolvedMediaDestinationView: View {
    let route: PlexMediaRoute
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var historyStore: PlexHistoryStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    @State private var item: PlexMediaItem?
    @State private var refreshesInitialMetadata = true
    @State private var errorMessage: String?
    @State private var resolutionID = UUID()

    var body: some View {
        Group {
            if let item {
                PlexMediaDestinationView(
                    initialItem: item,
                    browserStore: browserStore,
                    historyStore: historyStore,
                    settingsStore: settingsStore,
                    connectionStore: connectionStore,
                    playerCoordinator: playerCoordinator,
                    refreshesInitialMetadata: refreshesInitialMetadata
                )
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Item", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again", action: retry)
                }
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading media details")
            }
        }
        .task(id: resolutionID) {
            await resolve()
        }
    }

    private func retry() {
        resolutionID = UUID()
    }

    private func resolve() async {
        errorMessage = nil

        do {
            if let cachedItem = browserStore.item(for: route) {
                refreshesInitialMetadata = true
                item = cachedItem
            } else {
                let resolvedItem = try await browserStore.resolveItem(for: route)
                refreshesInitialMetadata = false
                item = resolvedItem
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}

private struct PlexAccountRequiredView: View {
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var authStore: PlexAuthStore

    var body: some View {
        ContentUnavailableView {
            Label("Not Signed In", systemImage: "person.crop.circle")
        } description: {
            if let progressMessage = authStore.signInProgressMessage {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressMessage)
                }
            } else if let errorMessage = authStore.errorMessage
                ?? settingsStore.credentialPersistenceErrorMessage {
                Text(errorMessage)
            }
        } actions: {
            if authStore.canCancelSignIn {
                Button("Cancel", role: .cancel) {
                    authStore.cancelSignIn()
                }
            } else if !authStore.isAuthenticating {
                Button("Sign In to Plex") {
                    authStore.startSignIn()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("PlexBar")
    }
}

private struct PlexServerRequiredView: View {
    @Bindable var authStore: PlexAuthStore

    var body: some View {
        ContentUnavailableView {
            Label("No Server Selected", systemImage: "server.rack")
        } actions: {
            if authStore.isLoadingServers {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Refresh Servers") {
                    Task {
                        await authStore.refreshServers(autoSelectStoredServer: true)
                    }
                }
            }
        }
        .navigationTitle("PlexBar")
    }
}

private struct PlexActivityView: View {
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var sessionStore: PlexSessionStore

    var body: some View {
        Group {
            if sessionStore.lastHydratedAt == nil || sessionStore.sessions.isEmpty {
                if let message = sessionStore.activityErrorMessage {
                    ContentUnavailableView {
                        Label("Activity Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { sessionStore.refreshNow() }
                            .disabled(sessionStore.isLoading)
                    }
                } else if sessionStore.lastHydratedAt == nil {
                    ProgressView("Loading activity…")
                } else {
                    ContentUnavailableView(
                        "No Active Streams",
                        systemImage: "play.rectangle"
                    )
                }
            } else {
                activeStreams
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Activity")
        .modifier(PlexActivityVisibility(store: sessionStore))
    }

    private var activeStreams: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    PlexActivitySummaryView(
                        summary: sessionStore.activitySummary,
                        isStale: sessionStore.activityErrorMessage != nil
                    )
                    if sessionStore.isLoading {
                        ProgressView().controlSize(.small)
                    }
                }

                if let message = sessionStore.activityErrorMessage {
                    InlineWarningBanner(message: message)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(sessionStore.sessions) { session in
                        StreamCardView(
                            session: session,
                            sessionStore: sessionStore,
                            onRequestTerminate: { _ in },
                            isShowingTerminatePrompt: false,
                            terminateMessage: .constant(""),
                            onCancelTerminate: {},
                            onConfirmTerminate: { _ in },
                            serverURL: connectionStore.resolvedServerURL,
                            settingsStore: settingsStore,
                            snapshotDate: sessionStore.lastUpdated,
                            resolvedLocation: sessionStore.resolvedLocation(for: session)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scenePadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
