import Foundation
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

    @Test func improvedMeasuredBandwidthSuggestsTheHighestSafeUpgrade() throws {
        var metrics = PlexPlaybackMetricFacts()
        metrics.recordBandwidthSample(try bandwidthSample(megabitsPerSecond: 5))
        metrics.recordBandwidthSample(try bandwidthSample(megabitsPerSecond: 8))

        let suggestion = try #require(makeSuggestion(
            selection: PlexVideoQualitySelection(
                selectedQuality: .hd4Mbps,
                isVideo: true,
                canChange: true
            ),
            metrics: metrics,
            sourceBitrate: 7_000
        ))

        #expect(suggestion.targetQuality == .original)
        #expect(suggestion.reason == .improvedBandwidth)
        #expect(suggestion.message ==
            "Playback bandwidth increased. Change to Original for this item?")
    }

    @Test func improvedBandwidthRespectsTheSavedMaximumQuality() throws {
        var metrics = PlexPlaybackMetricFacts()
        metrics.recordBandwidthSample(try bandwidthSample(megabitsPerSecond: 8))
        metrics.recordBandwidthSample(try bandwidthSample(megabitsPerSecond: 15))

        #expect(makeSuggestion(
            selection: PlexVideoQualitySelection(
                selectedQuality: .hd4Mbps,
                isVideo: true,
                canChange: true
            ),
            metrics: metrics,
            sourceBitrate: 18_000,
            maximumQuality: .fullHD8Mbps
        )?.targetQuality == .fullHD8Mbps)
    }

    @Test func upgradeRequiresAnIncreasingMeasurementAndALowerQualityTranscode() throws {
        var oneSample = PlexPlaybackMetricFacts()
        oneSample.recordBandwidthSample(try bandwidthSample(megabitsPerSecond: 15))

        var decreasing = oneSample
        decreasing.recordBandwidthSample(try bandwidthSample(megabitsPerSecond: 12))

        let selection = PlexVideoQualitySelection(
            selectedQuality: .hd4Mbps,
            isVideo: true,
            canChange: true
        )
        #expect(makeSuggestion(
            selection: selection,
            metrics: oneSample,
            sourceBitrate: 10_000
        ) == nil)
        #expect(makeSuggestion(
            selection: selection,
            metrics: decreasing,
            sourceBitrate: 10_000
        ) == nil)
        #expect(makeSuggestion(
            selection: selection,
            isTranscoding: false,
            metrics: try increasingBandwidthMetrics(),
            sourceBitrate: 10_000
        ) == nil)
        #expect(makeSuggestion(
            selection: selection,
            metrics: try increasingBandwidthMetrics(),
            sourceBitrate: 4_000
        ) == nil)
    }

    @Test func repeatedStallsTakePriorityOverAnAvailableUpgrade() throws {
        var metrics = try increasingBandwidthMetrics()
        metrics.recordStall()
        metrics.recordStall()
        metrics.recordStall()

        let suggestion = try #require(makeSuggestion(
            selection: PlexVideoQualitySelection(
                selectedQuality: .fullHD8Mbps,
                isVideo: true,
                canChange: true
            ),
            metrics: metrics,
            sourceBitrate: 18_000
        ))

        #expect(suggestion.targetQuality == .hd4Mbps)
        #expect(suggestion.reason == .repeatedStalls(count: 3))
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
        isTranscoding: Bool = true,
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
            isTranscoding: isTranscoding,
            metrics: metrics,
            excludedQualities: excludedQualities
        )
    }

    private func increasingBandwidthMetrics() throws -> PlexPlaybackMetricFacts {
        var metrics = PlexPlaybackMetricFacts()
        metrics.recordBandwidthSample(try bandwidthSample(megabitsPerSecond: 5))
        metrics.recordBandwidthSample(try bandwidthSample(megabitsPerSecond: 12))
        return metrics
    }

    private func bandwidthSample(
        megabitsPerSecond: Double
    ) throws -> PlexPlaybackBandwidthSample {
        let duration: TimeInterval = 1
        let byteCount = Int64(megabitsPerSecond * 1_000_000 * duration / 8)
        return try #require(PlexPlaybackBandwidthSample(
            byteCount: byteCount,
            responseStartTime: Date(timeIntervalSince1970: 100),
            responseEndTime: Date(timeIntervalSince1970: 100 + duration),
            wasReadFromCache: false,
            hadError: false
        ))
    }
}
