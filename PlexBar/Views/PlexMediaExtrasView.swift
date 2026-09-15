import PlexModels
import SwiftUI

struct PlexMediaExtrasView: View {
    let item: PlexMediaItem
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator

    var body: some View {
        Group {
            if isLoading, extras.isEmpty {
                ProgressView("Loading Extras")
                    .frame(maxWidth: 980, minHeight: 120)
                    .accessibilityLabel("Loading Extras")
            } else if let errorMessage, extras.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t Load Extras", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again", action: refresh)
                }
                .frame(maxWidth: 980, minHeight: 180)
            } else if !extras.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if let errorMessage {
                        HStack(spacing: 10) {
                            Label("Extras Didn’t Refresh", systemImage: "exclamationmark.triangle")
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer()
                            Button("Try Again", action: refresh)
                        }
                        .font(.callout)
                        .frame(maxWidth: 980, alignment: .leading)
                    }

                    PlexMediaShelf(
                        title: "Extras",
                        items: extras,
                        artworkLayout: .automatic,
                        showAllRoute: nil,
                        browserStore: browserStore,
                        settingsStore: settingsStore,
                        connectionStore: connectionStore,
                        playerCoordinator: playerCoordinator
                    )
                }
                .overlay(alignment: .top) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .accessibilityLabel("Refreshing Extras")
                    }
                }
            }
        }
    }

    private var extras: [PlexMediaItem] {
        browserStore.mediaExtras(for: item)
    }

    private var isLoading: Bool {
        browserStore.isLoadingMediaExtras(for: item)
    }

    private var errorMessage: String? {
        browserStore.mediaExtrasErrorMessage(for: item)
    }

    private func refresh() {
        Task {
            await browserStore.loadMediaExtras(for: item, forceRefresh: true)
        }
    }
}
