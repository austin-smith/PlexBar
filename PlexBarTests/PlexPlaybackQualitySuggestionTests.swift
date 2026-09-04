import Testing
@testable import PlexBar

struct PlexPlaybackQualitySuggestionTests {
    @Test func threeAuthoritativeStallsSuggestTheNextLowerQuality() throws {
        var metrics = PlexPlaybackMetricFacts()
        metrics.recordStall()
        metrics.recordStall()
        #expect(makeSuggestion(metrics: metrics, sourceBitrate: 7_000) == nil)

        metrics.recordStall()
        let qualitySuggestion = try #require(makeSuggestion(
            metrics: metrics,
            sourceBitrate: 7_000
        ))

        #expect(qualitySuggestion.targetQuality == .hd4Mbps)
        #expect(qualitySuggestion.reason == .repeatedStalls(count: 3))
        #expect(qualitySuggestion.message ==
            "Playback stalled 3 times. Change to 720p · 4 Mbps for this item?")
    }

    @Test func savedMaximumQualityCapsTheSuggestedTarget() {
        var metrics = PlexPlaybackMetricFacts()
        metrics.recordStall()
        metrics.recordStall()
        metrics.recordStall()

        #expect(makeSuggestion(
            metrics: metrics,
            sourceBitrate: 14_000,
            maximumQuality: .hd2Mbps
        )?.targetQuality == .hd2Mbps)
    }

    @Test func policyNeverGuessesWithoutAChangeableLowerQuality() {
        var metrics = PlexPlaybackMetricFacts()
        metrics.recordStall()
        metrics.recordStall()
        metrics.recordStall()

        #expect(makeSuggestion(
            isEnabled: false,
            metrics: metrics,
            sourceBitrate: 8_000
        ) == nil)
        #expect(makeSuggestion(
            selection: PlexVideoQualitySelection(
                selectedQuality: .original,
                isVideo: true,
                canChange: false
            ),
            metrics: metrics,
            sourceBitrate: 8_000
        ) == nil)
        #expect(makeSuggestion(metrics: metrics, sourceBitrate: nil) == nil)
        #expect(makeSuggestion(
            selection: PlexVideoQualitySelection(
                selectedQuality: .sd1500Kbps,
                isVideo: true,
                canChange: true
            ),
            metrics: metrics,
            sourceBitrate: 8_000
        ) == nil)
    }

    @Test func acceptedTargetsAreNotRepeated() {
        var metrics = PlexPlaybackMetricFacts()
        metrics.recordStall()
        metrics.recordStall()
        metrics.recordStall()

        #expect(makeSuggestion(
            metrics: metrics,
            sourceBitrate: 7_000,
            excludedQualities: [.hd4Mbps]
        ) == nil)
    }

    @Test func sessionStateKeepsUserIntentForTheCurrentItemOnly() {
        var state = PlexPlaybackQualitySuggestionSessionState()
        state.beginSession(itemKey: "movie-1")
        state.recordAccepted(.hd4Mbps)

        state.moveToItem(itemKey: "movie-1")
        #expect(state.acceptedQualities == [.hd4Mbps])
        #expect(!state.isSuppressed)

        state.suppress()
        #expect(state.isSuppressed)

        state.moveToItem(itemKey: "movie-2")
        #expect(state.itemKey == "movie-2")
        #expect(state.acceptedQualities.isEmpty)
        #expect(!state.isSuppressed)

        state.reset()
        #expect(state.itemKey == nil)
    }

    private func makeSuggestion(
        isEnabled: Bool = true,
        selection: PlexVideoQualitySelection = PlexVideoQualitySelection(
            selectedQuality: .original,
            isVideo: true,
            canChange: true
        ),
        metrics: PlexPlaybackMetricFacts,
        sourceBitrate: Int?,
        maximumQuality: PlexVideoQuality = .original,
        excludedQualities: Set<PlexVideoQuality> = []
    ) -> PlexPlaybackQualitySuggestion? {
        PlexPlaybackQualitySuggestionPolicy.suggestion(
            isEnabled: isEnabled,
            selection: selection,
            sourceBitrate: sourceBitrate,
            maximumQuality: maximumQuality,
            metrics: metrics,
            excludedQualities: excludedQualities
        )
    }
}
