import PlexClientKit
import PlexModels
import SwiftUI

struct PlexRelatedContentView: View {
    let item: PlexMediaItem
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator

    var body: some View {
        Group {
            if isLoading, hubs.isEmpty {
                ProgressView("Loading Related Content")
                    .frame(maxWidth: 980, minHeight: 120)
                    .accessibilityLabel("Loading Related Content")
            } else if let errorMessage, hubs.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t Load Related Content", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again", action: refresh)
                }
                .frame(maxWidth: 980, minHeight: 180)
            } else if !hubs.isEmpty {
                LazyVStack(alignment: .leading, spacing: 30) {
                    if let errorMessage {
                        HStack(spacing: 10) {
                            Label("Related Content Didn’t Refresh", systemImage: "exclamationmark.triangle")
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer()
                            Button("Try Again", action: refresh)
                        }
                        .font(.callout)
                        .frame(maxWidth: 980, alignment: .leading)
                    }

                    ForEach(hubs) { hub in
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
                .overlay(alignment: .top) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .accessibilityLabel("Refreshing Related Content")
                    }
                }
            }
        }
    }

    private var hubs: [PlexHub] {
        browserStore.relatedHubs(for: item)
    }

    private var isLoading: Bool {
        browserStore.isLoadingRelatedContent(for: item)
    }

    private var errorMessage: String? {
        browserStore.relatedContentErrorMessage(for: item)
    }

    private func refresh() {
        Task {
            await browserStore.loadRelatedContent(for: item, forceRefresh: true)
        }
    }

    private func showAllRoute(for hub: PlexHub) -> PlexNavigationRoute? {
        let totalSize = hub.totalSize ?? hub.size ?? hub.metadata.count
        guard hub.more || totalSize > hub.metadata.count,
              let route = PlexRelatedHubRoute(sourceItem: item, hub: hub) else {
            return nil
        }
        return .relatedHub(route)
    }
}

struct PlexRelatedHubItemsView: View {
    let route: PlexRelatedHubRoute
    let hub: PlexHub
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    private let artworkPrefetcher = PlexArtworkPrefetcher.shared

    var body: some View {
        Group {
            if isLoading, items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading \(hub.title)")
            } else if let errorMessage, items.isEmpty {
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
                        if let errorMessage {
                            PlexRelatedHubErrorRow(
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
                                    await browserStore.loadMoreRelatedHubItemsIfNeeded(
                                        for: route,
                                        currentItem: item
                                    )
                                }
                            }

                            if isLoading {
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
            if isLoading, !items.isEmpty {
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
                isEnabled: !isLoading,
                perform: refresh
            )
        )
        .task(id: route) {
            await browserStore.loadRelatedHubItems(for: route)
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh \(hub.title)", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(isLoading)
            }
        }
    }

    private var items: [PlexMediaItem] {
        browserStore.relatedHubItems(for: route)
    }

    private var isLoading: Bool {
        browserStore.isLoadingRelatedHubItems(for: route)
    }

    private var errorMessage: String? {
        browserStore.relatedHubItemsErrorMessage(for: route)
    }

    private func refresh() {
        Task {
            await browserStore.loadRelatedHubItems(for: route, forceRefresh: true)
        }
    }

    private func retryPageLoad() {
        guard let lastItem = items.last,
              browserStore.hasMoreRelatedHubItems(for: route) else {
            refresh()
            return
        }
        Task {
            await browserStore.loadMoreRelatedHubItemsIfNeeded(
                for: route,
                currentItem: lastItem
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

private struct PlexRelatedHubErrorRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label("Couldn’t Update Related Content", systemImage: "exclamationmark.triangle")
            Text(message)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Try Again", action: retry)
        }
        .accessibilityElement(children: .contain)
    }
}
