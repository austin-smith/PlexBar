import CoreGraphics
import Foundation
import Testing
@testable import PlexBar

struct PlexPlaybackMetricsTests {
    @Test func metricsRemainAbsentUntilAVFoundationPublishesEvidence() {
        let facts = PlexPlaybackMetricFacts()

        #expect(!facts.receivedEvent)
        #expect(facts.diagnosticFacts.isEmpty)
    }

    @Test func initialStartupStallsAndVariantSwitchesRemainExactFacts() throws {
        let initialVariant = try #require(PlexPlaybackVariantFacts(
            presentationSize: CGSize(width: 1_920, height: 1_080),
            averageBitRate: 6_500_000,
            peakBitRate: 8_000_000
        ))
        let switchedVariant = try #require(PlexPlaybackVariantFacts(
            presentationSize: CGSize(width: 3_840, height: 2_160),
            averageBitRate: 15_250_000,
            peakBitRate: 20_000_000
        ))
        var facts = PlexPlaybackMetricFacts()

        facts.recordInitialLikelyToKeepUp(timeTaken: 1.23456, variant: initialVariant)
        facts.recordStall()
        facts.recordStall()
        facts.recordVariantSwitch(succeeded: true, to: switchedVariant)
        facts.recordVariantSwitch(succeeded: false, to: initialVariant)

        #expect(facts.initialStartupTime == 1.23456)
        #expect(facts.stallCount == 2)
        #expect(facts.successfulVariantSwitchCount == 1)
        #expect(facts.failedVariantSwitchCount == 1)
        #expect(facts.currentVariant == switchedVariant)
        #expect(facts.diagnosticFacts.map { "\($0.label): \($0.value)" } == [
            "Initial Startup: 1.235 sec",
            "Playback Stalls: 2",
            "Successful Variant Switches: 1",
            "Failed Variant Switches: 1",
            "Current Variant: 3840 × 2160 · 15.25 Mbps average · 20 Mbps peak",
        ])
        #expect(Set(facts.diagnosticFacts.map(\.id)).count == facts.diagnosticFacts.count)
    }

    @Test func failedSwitchNeverBecomesTheCurrentVariant() throws {
        let currentVariant = try #require(PlexPlaybackVariantFacts(
            presentationSize: CGSize(width: 1_920, height: 1_080),
            averageBitRate: nil,
            peakBitRate: nil
        ))
        let rejectedVariant = try #require(PlexPlaybackVariantFacts(
            presentationSize: CGSize(width: 3_840, height: 2_160),
            averageBitRate: nil,
            peakBitRate: nil
        ))
        var facts = PlexPlaybackMetricFacts()

        facts.recordInitialLikelyToKeepUp(timeTaken: 0, variant: currentVariant)
        facts.recordVariantSwitch(succeeded: false, to: rejectedVariant)

        #expect(facts.currentVariant == currentVariant)
        #expect(facts.diagnosticFacts.map { "\($0.label): \($0.value)" } == [
            "Initial Startup: 0 sec",
            "Playback Stalls: 0",
            "Failed Variant Switches: 1",
            "Current Variant: 1920 × 1080",
        ])
    }

    @Test func invalidMetricValuesAreOmittedRatherThanRoundedOrGuessed() {
        #expect(PlexPlaybackVariantFacts(
            presentationSize: CGSize(width: 1_920.5, height: 1_080),
            averageBitRate: -.infinity,
            peakBitRate: 0
        ) == nil)

        var facts = PlexPlaybackMetricFacts()
        facts.recordInitialLikelyToKeepUp(timeTaken: .nan, variant: nil)

        #expect(facts.initialStartupTime == nil)
        #expect(facts.diagnosticFacts.map { "\($0.label): \($0.value)" } == [
            "Playback Stalls: 0",
        ])
    }

    @Test func networkBandwidthUsesExactResponseBytesAndTransferInterval() throws {
        let responseStart = Date(timeIntervalSince1970: 100)
        let responseEnd = Date(timeIntervalSince1970: 102)
        let sample = try #require(PlexPlaybackBandwidthSample(
            byteCount: 2_000_000,
            responseStartTime: responseStart,
            responseEndTime: responseEnd,
            wasReadFromCache: false,
            hadError: false
        ))
        var facts = PlexPlaybackMetricFacts()
        facts.recordBandwidthSample(sample)

        #expect(sample.bitsPerSecond == 8_000_000)
        #expect(sample.measuredAt == responseEnd)
        #expect(sample.byteCount == 2_000_000)
        #expect(sample.transferDuration == 2)
        #expect(facts.lastMeasuredBandwidth == sample)
        #expect(facts.diagnosticFacts.last == PlexPlaybackMetricDiagnosticFact(
            kind: .measuredBandwidth,
            label: "Last Measured Bandwidth",
            value: "8 Mbps"
        ))
    }

    @Test func cachedFailedEmptyAndInvalidTransfersNeverBecomeBandwidthFacts() {
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 101)

        #expect(PlexPlaybackBandwidthSample(
            byteCount: 1,
            responseStartTime: start,
            responseEndTime: end,
            wasReadFromCache: true,
            hadError: false
        ) == nil)
        #expect(PlexPlaybackBandwidthSample(
            byteCount: 1,
            responseStartTime: start,
            responseEndTime: end,
            wasReadFromCache: false,
            hadError: true
        ) == nil)
        #expect(PlexPlaybackBandwidthSample(
            byteCount: 0,
            responseStartTime: start,
            responseEndTime: end,
            wasReadFromCache: false,
            hadError: false
        ) == nil)
        #expect(PlexPlaybackBandwidthSample(
            byteCount: 1,
            responseStartTime: end,
            responseEndTime: start,
            wasReadFromCache: false,
            hadError: false
        ) == nil)
    }
}
