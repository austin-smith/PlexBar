@testable import PlexClientKit
import Testing
@testable import PlexBar

struct PlexVideoQualityPreferencesTests {
    @Test func selectsHomeQualityOnlyForLocalConnections() {
        let preferences = PlexVideoQualityPreferences(
            local: .original,
            remote: .hd4Mbps
        )

        #expect(preferences.quality(for: .local) == .original)
        #expect(preferences.quality(for: .remote) == .hd4Mbps)
        #expect(preferences.quality(for: .relay) == .hd4Mbps)
        #expect(preferences.quality(for: nil) == .hd4Mbps)
    }

    @Test func musicQualityIsOriginalAtHomeAndUsesTheRemoteCeilingEverywhereElse() {
        let preferences = PlexMusicQualityPreferences(remote: .kbps192)

        #expect(preferences.quality(for: .local) == .original)
        #expect(preferences.quality(for: .remote) == .kbps192)
        #expect(preferences.quality(for: .relay) == .kbps192)
        #expect(preferences.quality(for: nil) == .kbps192)
    }
}
