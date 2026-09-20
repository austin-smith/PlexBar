import SwiftUI

struct TVLibrariesView: View {
    @Environment(TVAppStore.self) private var store

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: TVLayout.cardSpacing, alignment: .top),
        count: 5
    )

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoadingLibraries, store.libraries.isEmpty {
                    TVLoadingView(title: "Loading Libraries…")
                } else if store.libraries.isEmpty {
                    ContentUnavailableView(
                        "No Libraries",
                        systemImage: "rectangle.stack.badge.minus",
                        description: Text("No libraries are available on this server.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: TVLayout.sectionSpacing) {
                            ForEach(store.libraries) { library in
                                NavigationLink(value: library) {
                                    TVLibraryLockup(library: library)
                                }
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
            .navigationDestination(for: TVPlexLibrary.self) { library in
                TVLibraryDetailView(library: library)
            }
            .navigationDestination(for: TVNavigationRoute.self) { route in
                TVNavigationDestination(route: route)
            }
        }
    }
}

private struct TVLibraryLockup: View {
    let library: TVPlexLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TVPlexArtwork(
                path: library.artworkPath,
                width: 960,
                height: 540,
                systemImage: icon,
                usesOriginalImage: true
            )
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 12))
            .hoverEffect(.highlight)

            TVMediaCardLabels(title: library.title, subtitle: library.type.capitalized)
        }
    }

    private var icon: String {
        switch library.type.lowercased() {
        case "movie": "film.stack"
        case "show": "tv"
        case "artist": "music.note.list"
        default: "rectangle.stack"
        }
    }
}
