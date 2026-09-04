import SwiftUI

struct PlexMediaHubShelf: View {
    let hub: PlexHub
    let showAllRoute: PlexNavigationRoute?
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator

    var body: some View {
        PlexMediaShelf(
            title: hub.title,
            items: hub.metadata,
            artworkLayout: hub.prefersPosterArtwork ? .poster : .automatic,
            allowsRemovalFromContinueWatching: hub.isContinueWatching,
            showAllRoute: showAllRoute,
            browserStore: browserStore,
            settingsStore: settingsStore,
            connectionStore: connectionStore,
            playerCoordinator: playerCoordinator
        )
    }
}

struct PlexMediaShelf: View {
    let title: String
    let items: [PlexMediaItem]
    let artworkLayout: PlexMediaPosterCard.ArtworkLayout
    var allowsRemovalFromContinueWatching = false
    let showAllRoute: PlexNavigationRoute?
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 180
    private let artworkPrefetcher = PlexArtworkPrefetcher.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if let showAllRoute {
                    NavigationLink("Show All", value: showAllRoute)
                }
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(items) { item in
                        NavigationLink(value: PlexNavigationRoute.media(PlexMediaRoute(item: item))) {
                            PlexMediaPosterCard(
                                item: item,
                                settingsStore: settingsStore,
                                serverURL: connectionStore.resolvedServerURL,
                                artworkLayout: artworkLayout
                            )
                            .frame(width: cardWidth, alignment: .topLeading)
                        }
                        .plexMediaContextMenu(
                            for: item,
                            allowsRemovalFromContinueWatching: allowsRemovalFromContinueWatching,
                            browserStore: browserStore,
                            playerCoordinator: playerCoordinator
                        )
                        .buttonStyle(.plain)
                        .task {
                            await prefetchArtwork(after: item)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func prefetchArtwork(after item: PlexMediaItem) async {
        guard let itemIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let requests = items
            .dropFirst(itemIndex + 1)
            .prefix(6)
            .compactMap {
                PlexMediaPosterCard.prefetchRequest(
                    for: $0,
                    serverURL: connectionStore.resolvedServerURL,
                    token: settingsStore.trimmedServerToken,
                    clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                    artworkLayout: artworkLayout,
                    spoilerPolicy: settingsStore.episodeSpoilerPolicy
                )
            }
        await artworkPrefetcher.prefetch(requests)
    }
}

struct PlexMediaGridSection: View {
    let title: String
    let items: [PlexMediaItem]
    let artworkLayout: PlexMediaPosterCard.ArtworkLayout
    var allowsRemovalFromContinueWatching = false
    var showAllRoute: PlexNavigationRoute? = nil
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if let showAllRoute {
                    NavigationLink("Show All", value: showAllRoute)
                }
            }

            PlexMediaPosterGrid(
                items: items,
                artworkLayout: artworkLayout,
                allowsRemovalFromContinueWatching: allowsRemovalFromContinueWatching,
                browserStore: browserStore,
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                playerCoordinator: playerCoordinator
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct PlexMediaPosterGrid: View {
    let items: [PlexMediaItem]
    let artworkLayout: PlexMediaPosterCard.ArtworkLayout
    var allowsRemovalFromContinueWatching = false
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    private let artworkPrefetcher = PlexArtworkPrefetcher.shared

    var body: some View {
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
                        artworkLayout: artworkLayout
                    )
                }
                .plexMediaContextMenu(
                    for: item,
                    allowsRemovalFromContinueWatching: allowsRemovalFromContinueWatching,
                    browserStore: browserStore,
                    playerCoordinator: playerCoordinator
                )
                .buttonStyle(.plain)
                .task {
                    await prefetchArtwork(after: item)
                }
            }
        }
    }

    private func prefetchArtwork(after item: PlexMediaItem) async {
        guard let itemIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let requests = items
            .dropFirst(itemIndex + 1)
            .prefix(6)
            .compactMap {
                PlexMediaPosterCard.prefetchRequest(
                    for: $0,
                    serverURL: connectionStore.resolvedServerURL,
                    token: settingsStore.trimmedServerToken,
                    clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                    artworkLayout: artworkLayout,
                    spoilerPolicy: settingsStore.episodeSpoilerPolicy
                )
            }
        await artworkPrefetcher.prefetch(requests)
    }
}
