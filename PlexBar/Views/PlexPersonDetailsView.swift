import PlexModels
import SwiftUI

struct PlexPersonDetailsView: View {
    let route: PlexPersonRoute
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    @ScaledMetric(relativeTo: .body) private var portraitSize: CGFloat = 180

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header

                if isLoading, media.isEmpty {
                    ProgressView("Loading appearances…")
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .accessibilityLabel("Loading appearances for \(displayName)")
                } else if let errorMessage, media.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn’t Load Appearances", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again", action: refresh)
                    }
                    .frame(maxWidth: 980, minHeight: 180)
                } else if media.isEmpty {
                    ContentUnavailableView(
                        "No Appearances in This Library",
                        systemImage: "rectangle.stack"
                    )
                    .frame(maxWidth: 980, minHeight: 180)
                } else {
                    PlexMediaGridSection(
                        title: "In Your Library",
                        items: media,
                        artworkLayout: .poster,
                        browserStore: browserStore,
                        settingsStore: settingsStore,
                        connectionStore: connectionStore,
                        playerCoordinator: playerCoordinator
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding()
        }
        .navigationTitle(displayName)
        .focusedSceneValue(
            \.plexRefreshCommand,
            PlexFocusedCommandAction(
                title: "Reload \(displayName)",
                isEnabled: !isLoading,
                perform: refresh
            )
        )
        .task(id: route) {
            await browserStore.loadPerson(route)
        }
        .toolbar {
            ToolbarItem {
                Button("Reload \(displayName)", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(isLoading)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            PlexArtworkView(
                primaryImageURL: portraitRequest?.url,
                fallbackImageURL: nil,
                token: portraitRequest?.token ?? "",
                clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                placeholderSymbol: "person.crop.square",
                width: portraitSize,
                height: portraitSize,
                cornerRadius: 20
            )

            Text(displayName)
                .font(.largeTitle.weight(.semibold))
                .frame(maxWidth: 680, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var person: PlexTag? {
        browserStore.person(for: route)
    }

    private var displayName: String {
        person?.tag.nilIfBlank ?? route.name
    }

    private var media: [PlexMediaItem] {
        browserStore.personMedia(for: route)
    }

    private var isLoading: Bool {
        browserStore.isLoadingPerson(route)
    }

    private var errorMessage: String? {
        browserStore.personErrorMessage(for: route)
    }

    private var portraitRequest: PlexImageRequest? {
        PlexImageRequest(
            path: person?.thumb?.nilIfBlank ?? route.thumb,
            serverURL: connectionStore.resolvedServerURL,
            serverToken: settingsStore.trimmedServerToken
        )
    }

    private func refresh() {
        Task {
            await browserStore.loadPerson(route, forceRefresh: true)
        }
    }
}
