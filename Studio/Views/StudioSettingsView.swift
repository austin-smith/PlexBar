import SwiftUI

struct StudioSettingsView: View {
    let store: StudioStore

    var body: some View {
        TabView {
            Tab("Artwork", systemImage: "paintpalette") {
                StudioArtworkStyleSettings(store: store)
            }
            Tab("Codex", systemImage: "terminal") {
                StudioCodexSettings()
            }
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}
