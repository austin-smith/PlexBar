import PlexModels
import SwiftUI

struct PlexGlobalSearchView: View {
    @Bindable var searchStore: PlexGlobalSearchStore
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator

    var body: some View {
        Group {
            if searchStore.normalizedQuery.isEmpty {
                ContentUnavailableView("Search", systemImage: "magnifyingglass")
            } else if searchStore.isSearching, searchStore.visibleHubs.isEmpty {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Searching for \(searchStore.normalizedQuery)")
            } else if let errorMessage = searchStore.errorMessage,
                      searchStore.visibleHubs.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t Search", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again", action: refresh)
                }
            } else if searchStore.hasSearched, searchStore.visibleHubs.isEmpty {
                ContentUnavailableView.search(text: searchStore.displayedQuery)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        if let errorMessage = searchStore.errorMessage {
                            PlexGlobalSearchErrorRow(
                                message: errorMessage,
                                retry: refresh
                            )
                        }

                        ForEach(searchStore.visibleHubs) { hub in
                            PlexMediaGridSection(
                                title: hub.title,
                                items: hub.metadata,
                                artworkLayout: hub.prefersPosterArtwork ? .poster : .automatic,
                                showAllRoute: showAllRoute(for: hub),
                                browserStore: browserStore,
                                settingsStore: settingsStore,
                                connectionStore: connectionStore,
                                playerCoordinator: playerCoordinator
                            )
                        }
                    }
                    .scenePadding()
                }
            }
        }
        .overlay(alignment: .top) {
            if searchStore.isSearching, !searchStore.visibleHubs.isEmpty {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Searching for \(searchStore.normalizedQuery)")
            }
        }
        .navigationTitle("Search Results")
        .focusedSceneValue(
            \.plexRefreshCommand,
            PlexFocusedCommandAction(
                title: "Refresh Search Results",
                isEnabled: !searchStore.normalizedQuery.isEmpty && !searchStore.isSearching,
                perform: refresh
            )
        )
        .task {
            await browserStore.loadLibraryProviderCapabilities()
        }
        .task(id: searchStore.normalizedQuery) {
            await searchStore.update(load: search)
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh Search Results", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(searchStore.normalizedQuery.isEmpty || searchStore.isSearching)
            }
        }
    }

    private func search(_ query: String) async throws -> [PlexHub] {
        try await browserStore.searchAllLibraries(query: query)
    }

    private func refresh() {
        Task {
            await searchStore.update(forceRefresh: true, load: search)
        }
    }

    private func showAllRoute(for hub: PlexHub) -> PlexNavigationRoute? {
        let totalSize = hub.totalSize ?? hub.size ?? hub.metadata.count
        guard hub.more || totalSize > hub.metadata.count,
              let route = PlexSearchHubRoute(
                  hub: hub,
                  query: searchStore.displayedQuery
              ) else {
            return nil
        }
        return .searchHub(route)
    }
}

struct PlexSearchHubItemsView: View {
    let hub: PlexHub
    @Bindable var searchStore: PlexGlobalSearchStore
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    private let artworkPrefetcher = PlexArtworkPrefetcher.shared

    var body: some View {
        Group {
            if searchStore.isLoadingItems(in: hub), items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading \(hub.title)")
            } else if let errorMessage = searchStore.itemsErrorMessage(in: hub),
                      items.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t Load \(hub.title)", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again", action: refresh)
                }
            } else if items.isEmpty {
                ContentUnavailableView("No Items", systemImage: "rectangle.stack")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let errorMessage = searchStore.itemsErrorMessage(in: hub) {
                            PlexGlobalSearchErrorRow(
                                message: errorMessage,
                                retry: retryPageLoad
                            )
                        }

                        LazyVGrid(
                            columns: PlexMediaPosterCard.standardGridColumns,
                            alignment: .leading,
                            spacing: 24
                        ) {
                            ForEach(items) { item in
                                NavigationLink(value: PlexNavigationRoute.media(PlexMediaRoute(item: item))) {
                                    PlexMediaPosterCard(
                                        item: item,
                                        settingsStore: settingsStore,
                                        serverURL: connectionStore.resolvedServerURL,
                                        artworkLayout: hub.prefersPosterArtwork ? .poster : .automatic
                                    )
                                }
                                .plexMediaContextMenu(
                                    for: item,
                                    browserStore: browserStore,
                                    playerCoordinator: playerCoordinator
                                )
                                .buttonStyle(.plain)
                                .task {
                                    await prefetchArtwork(after: item)
                                    await searchStore.loadMoreItemsIfNeeded(
                                        in: hub,
                                        currentItem: item,
                                        loadPage: loadPage
                                    )
                                }
                            }

                            if searchStore.isLoadingItems(in: hub) {
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 80)
                                    .accessibilityLabel("Loading more \(hub.title)")
                            }
                        }
                    }
                    .scenePadding()
                }
            }
        }
        .overlay(alignment: .top) {
            if searchStore.isLoadingItems(in: hub), !items.isEmpty {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Refreshing \(hub.title)")
            }
        }
        .navigationTitle(hub.title)
        .focusedSceneValue(
            \.plexRefreshCommand,
            PlexFocusedCommandAction(
                title: "Refresh \(hub.title)",
                isEnabled: !searchStore.isLoadingItems(in: hub),
                perform: refresh
            )
        )
        .task(id: hub.key) {
            await searchStore.loadItems(in: hub, loadPage: loadPage)
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh \(hub.title)", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(searchStore.isLoadingItems(in: hub))
            }
        }
    }

    private var items: [PlexMediaItem] {
        searchStore.items(in: hub)
    }

    private func loadPage(path: String, start: Int, size: Int) async throws -> PlexMediaPage {
        try await browserStore.globalSearchHubPage(
            path: path,
            start: start,
            size: size
        )
    }

    private func refresh() {
        Task {
            await searchStore.loadItems(
                in: hub,
                forceRefresh: true,
                loadPage: loadPage
            )
        }
    }

    private func retryPageLoad() {
        guard let lastItem = items.last,
              searchStore.hasMoreItems(in: hub) else {
            refresh()
            return
        }
        Task {
            await searchStore.loadMoreItemsIfNeeded(
                in: hub,
                currentItem: lastItem,
                loadPage: loadPage
            )
        }
    }

    private func prefetchArtwork(after item: PlexMediaItem) async {
        let currentItems = items
        guard let itemIndex = currentItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let requests = currentItems
            .dropFirst(itemIndex + 1)
            .prefix(6)
            .compactMap {
                PlexMediaPosterCard.prefetchRequest(
                    for: $0,
                    serverURL: connectionStore.resolvedServerURL,
                    token: settingsStore.trimmedServerToken,
                    clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                    artworkLayout: hub.prefersPosterArtwork ? .poster : .automatic,
                    spoilerPolicy: settingsStore.episodeSpoilerPolicy
                )
            }
        await artworkPrefetcher.prefetch(requests)
    }
}

struct PlexGlobalSearchErrorRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label("Couldn’t Update Search Results", systemImage: "exclamationmark.triangle")

            Text(message)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            Button("Try Again", action: retry)
        }
        .accessibilityElement(children: .contain)
    }
}
