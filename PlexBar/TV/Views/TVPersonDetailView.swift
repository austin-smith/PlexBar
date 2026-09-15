import PlexModels
import SwiftUI

struct TVPersonDetailView: View {
    @Environment(TVAppStore.self) private var store

    let route: PlexPersonRoute

    @State private var person: PlexTag?
    @State private var media: [PlexMediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
                header

                if isLoading, media.isEmpty {
                    ProgressView("Loading Appearances…")
                        .safeAreaPadding(.horizontal)
                } else if let errorMessage, media.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn’t Load Appearances", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again", systemImage: "arrow.clockwise", action: refresh)
                    }
                } else if media.isEmpty {
                    ContentUnavailableView(
                        "No Appearances in This Library",
                        systemImage: "rectangle.stack"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("In Your Library")
                            .font(TVTypography.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                        TVMediaGrid(items: media, artworkLayout: .poster)
                    }
                    .safeAreaPadding(.horizontal)
                }
            }
            .safeAreaPadding(.top, 40)
            .safeAreaPadding(.bottom)
        }
        .scrollClipDisabled()
        .background(TVCanvasBackground())
        .toolbarVisibility(.hidden, for: .tabBar)
        .task(id: route) {
            await load()
        }
        .navigationDestination(for: TVNavigationRoute.self) { route in
            TVNavigationDestination(route: route)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            TVPlexArtwork(
                path: person?.thumb?.nilIfBlank ?? route.thumb,
                width: 400,
                height: 400,
                systemImage: "person.fill"
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 180, height: 180)
            .clipShape(.rect(cornerRadius: 20))

            Text(displayName)
                .font(TVTypography.title)
                .lineLimit(2)
        }
        .safeAreaPadding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    private var displayName: String {
        person?.tag.nilIfBlank ?? route.name
    }

    private func refresh() {
        Task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let details = try await store.personDetails(for: route)
            try Task.checkCancellation()
            person = details.person
            media = details.media
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
