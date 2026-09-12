import SwiftUI

/// Only failures add an action at the end of the content. Normal pagination
/// requires no extra remote press and adds no focusable heading or footer.
struct TVHubLoadingStatus: View {
    @Environment(TVAppStore.self) private var store
    let hub: PlexHub
    let browser: TVHubBrowseStore

    var body: some View {
        if let error = browser.errorMessage {
            VStack(alignment: .leading, spacing: 12) {
                Text(error)
                    .font(TVTypography.metadata)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320, alignment: .leading)
                Button("Try Again", systemImage: "arrow.clockwise") {
                    Task {
                        await browser.retry(hub: hub, using: store)
                        if let last = browser.items.last {
                            await browser.loadInline(hub: hub, using: store, after: last)
                        }
                    }
                }
            }
        } else if browser.isLoading {
            ProgressView("Loading…")
        }
    }
}
