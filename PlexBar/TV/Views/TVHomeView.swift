import SwiftUI

struct TVHomeView: View {
    @Environment(TVAppStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationStack(path: $store.homePath) {
            Group {
                if store.isLoadingHome, store.homeHubs.isEmpty {
                    TVLoadingView(title: "Loading Home…")
                } else if store.homeHubs.isEmpty {
                    TVHomeEmptyView(refresh: refresh)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
                            ForEach(store.homeHubs) { hub in
                                TVMediaShelf(hub: hub, videoOnly: true)
                            }
                        }
                        .safeAreaPadding(.vertical)
                    }
                    .scrollClipDisabled()
                }
            }
            .background(TVCanvasBackground())
            .navigationDestination(for: TVNavigationRoute.self) { route in
                TVNavigationDestination(route: route)
            }
        }
    }

    private func refresh() {
        Task { await store.refreshAll() }
    }
}

struct TVMediaShelf: View {
    @Environment(TVAppStore.self) private var store
    @State private var browser: TVHubBrowseStore

    enum ArtworkPreference {
        case automatic
        case poster
        case landscape
    }

    let title: String
    let items: [PlexMediaItem]
    let artworkPreference: ArtworkPreference
    let columnCount: Int?
    private var hub: PlexHub?
    var showsEpisodeNumbers = false
    var selectedItemID: String?
    var selectItem: ((PlexMediaItem) -> Void)?

    init(hub: PlexHub, videoOnly: Bool = false) {
        _browser = State(initialValue: TVHubBrowseStore(videoOnly: videoOnly))
        self.hub = hub
        title = hub.title
        items = hub.metadata
        artworkPreference = hub.prefersPosterArtwork ? .poster : .automatic
        columnCount = nil
    }

    init(
        title: String,
        items: [PlexMediaItem],
        artworkPreference: ArtworkPreference = .automatic,
        columnCount: Int? = nil,
        showsEpisodeNumbers: Bool = false,
        selectedItemID: String? = nil,
        selectItem: ((PlexMediaItem) -> Void)? = nil
    ) {
        _browser = State(initialValue: TVHubBrowseStore())
        self.title = title
        self.items = items
        self.artworkPreference = artworkPreference
        self.columnCount = columnCount
        self.showsEpisodeNumbers = showsEpisodeNumbers
        self.selectedItemID = selectedItemID
        self.selectItem = selectItem
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Section {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: TVLayout.cardSpacing) {
                        ForEach(visibleItems) { item in
                            TVMediaLockup(
                                item: item,
                                artworkStyle: artworkStyle(for: item),
                                artworkLayout: artworkPreference == .poster ? .poster : .automatic,
                                columnCount: columnCount,
                                showsEpisodeNumber: showsEpisodeNumbers,
                                selectionAction: selectItem.map { action in { action(item) } },
                                isSelected: item.id == selectedItemID
                            )
                            .task(id: hub.map { TVHubBrowseStore.Identity(hub: $0, connection: store.connection) }) {
                                if let hub { await browser.loadInline(hub: hub, using: store, after: item) }
                            }
                        }
                        if let hub {
                            TVHubLoadingStatus(hub: hub, browser: browser)
                        }
                    }
                    .safeAreaPadding(.horizontal)
                }
                .scrollClipDisabled()
                .buttonStyle(.borderless)
            } header: {
                if !title.isEmpty {
                    Text(title)
                        .font(TVTypography.sectionTitle)
                        .safeAreaPadding(.horizontal)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .focusSection()
    }

    private var visibleItems: [PlexMediaItem] {
        guard let hub else { return items }
        return browser.visibleItems(hub: hub, connection: store.connection)
    }

    private func artworkStyle(for item: PlexMediaItem) -> PlexMediaArtworkShape {
        switch artworkPreference {
        case .automatic:
            return .automatic(for: item)
        case .poster:
            return .poster
        case .landscape:
            return .landscape
        }
    }
}

private struct TVHomeEmptyView: View {
    let refresh: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Home Content", systemImage: "rectangle.stack.badge.minus")
        } description: {
            Text("Plex did not return any promoted media from this server.")
        } actions: {
            Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
        }
    }
}
