import PlexClientKit
import PlexModels
import SwiftUI

struct PlexHomeView: View {
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator

    var body: some View {
        Group {
            if browserStore.isLoadingHomeHubs, browserStore.homeHubs.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading Home")
            } else if let errorMessage = browserStore.homeHubsErrorMessage,
                      browserStore.homeHubs.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t Load Home", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again", action: refresh)
                }
            } else if browserStore.hasLoadedHomeHubs, browserStore.homeHubs.isEmpty {
                ContentUnavailableView("No Home Content", systemImage: "house")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        ForEach(browserStore.homeHubs) { hub in
                            PlexMediaHubShelf(
                                hub: hub,
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
            if browserStore.isLoadingHomeHubs, !browserStore.homeHubs.isEmpty {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Refreshing Home")
            }
        }
        .navigationTitle("Home")
        .focusedSceneValue(
            \.plexRefreshCommand,
            PlexFocusedCommandAction(
                title: "Refresh Home",
                isEnabled: !browserStore.isLoadingHomeHubs,
                perform: refresh
            )
        )
        .task {
            async let capabilityLoad: Void = browserStore.loadLibraryProviderCapabilities()
            await browserStore.loadHomeHubs()
            _ = await capabilityLoad
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh Home", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(browserStore.isLoadingHomeHubs)
            }
        }
    }

    private func refresh() {
        Task {
            await browserStore.loadHomeHubs(forceRefresh: true)
        }
    }

    private func showAllRoute(for hub: PlexHub) -> PlexNavigationRoute? {
        guard hub.key != nil else {
            return nil
        }
        let totalSize = hub.totalSize ?? hub.size ?? hub.metadata.count
        guard hub.more || totalSize > hub.metadata.count else {
            return nil
        }
        return .homeHub(PlexHomeHubRoute(hub: hub))
    }
}

struct PlexHomeHubItemsView: View {
    let hub: PlexHub
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    private let artworkPrefetcher = PlexArtworkPrefetcher.shared

    var body: some View {
        Group {
            if browserStore.isLoadingHomeHubItems(in: hub), items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading \(hub.title)")
            } else if let errorMessage = browserStore.homeHubItemsErrorMessage(in: hub),
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
                                allowsRemovalFromContinueWatching: hub.isContinueWatching,
                                browserStore: browserStore,
                                playerCoordinator: playerCoordinator
                            )
                            .buttonStyle(.plain)
                            .task {
                                await prefetchArtwork(after: item)
                                await browserStore.loadMoreHomeHubItemsIfNeeded(
                                    in: hub,
                                    currentItem: item
                                )
                            }
                        }

                        if browserStore.isLoadingHomeHubItems(in: hub) {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 80)
                                .accessibilityLabel("Loading more \(hub.title)")
                        }
                    }
                    .scenePadding()
                }
            }
        }
        .overlay(alignment: .top) {
            if browserStore.isLoadingHomeHubItems(in: hub), !items.isEmpty {
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
                isEnabled: !browserStore.isLoadingHomeHubItems(in: hub),
                perform: refresh
            )
        )
        .task(id: hub.id) {
            await browserStore.loadHomeHubItems(in: hub)
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh \(hub.title)", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(browserStore.isLoadingHomeHubItems(in: hub))
            }
        }
    }

    private var items: [PlexMediaItem] {
        browserStore.homeHubItems(in: hub)
    }

    private func refresh() {
        Task {
            await browserStore.loadHomeHubItems(in: hub, forceRefresh: true)
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
