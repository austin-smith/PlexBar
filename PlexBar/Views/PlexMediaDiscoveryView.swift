import SwiftUI

struct PlexMediaDiscoveryView: View {
    let item: PlexMediaItem
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            PlexMediaExtrasView(
                item: item,
                browserStore: browserStore,
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                playerCoordinator: playerCoordinator
            )

            PlexRelatedContentView(
                item: item,
                browserStore: browserStore,
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                playerCoordinator: playerCoordinator
            )
        }
    }
}
