import PlexClientKit
import SwiftUI

struct TVSearchView: View {
    @Environment(TVAppStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Group {
                if store.isSearching, visibleHubs.isEmpty {
                    TVLoadingView(title: "Searching…")
                } else if store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Search Your Plex",
                        systemImage: "magnifyingglass",
                        description: Text("Find movies, shows, episodes, music, and collections.")
                    )
                } else if let error = store.searchErrorMessage {
                    ContentUnavailableView {
                        Label("Couldn’t Search Plex", systemImage: "magnifyingglass")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again", systemImage: "arrow.clockwise") { store.submitSearch() }
                    }
                } else if visibleHubs.isEmpty {
                    ContentUnavailableView.search(text: store.searchQuery)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
                            ForEach(visibleHubs) { hub in
                                TVSearchHubGrid(hub: hub)
                            }
                        }
                        .buttonStyle(.borderless)
                        .safeAreaPadding(.horizontal)
                        .safeAreaPadding(.vertical)
                    }
                    .scrollClipDisabled()
                }
            }
            .background(TVCanvasBackground())
            .searchable(text: $store.searchQuery, prompt: "Movies, shows, episodes, and music")
            .onSubmit(of: .search) {
                store.submitSearch()
            }
            .onChange(of: store.searchQuery) {
                store.submitSearch()
            }
            .onChange(of: store.connection) {
                store.submitSearch()
            }
            .navigationDestination(for: TVNavigationRoute.self) { route in
                TVNavigationDestination(route: route)
            }
        }
    }

    private var visibleHubs: [PlexHub] {
        store.searchHubs.filter { !$0.metadata.isEmpty }
    }
}
