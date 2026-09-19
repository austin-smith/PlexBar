import PlexClientKit
import SwiftUI

struct TVSearchHubGrid: View {
    @Environment(TVAppStore.self) private var store
    let hub: PlexHub
    @State private var browser = TVHubBrowseStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(hub.title)
                .font(TVTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            TVMediaGrid(
                items: browser.visibleItems(hub: hub, connection: store.connection),
                artworkLayout: hub.prefersPosterArtwork ? .poster : .automatic
            ) { item in
                await browser.loadInline(hub: hub, using: store, after: item)
            }
            TVHubLoadingStatus(hub: hub, browser: browser)
        }
        .focusSection()
    }
}
