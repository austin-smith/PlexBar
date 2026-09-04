import AVFoundation
import CoreGraphics
import Foundation

struct PlexPlaybackMetricDiagnosticFact: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case initialStartup
        case stalls
        case variantSwitches
        case failedVariantSwitches
        case currentVariant
        case measuredBandwidth
    }

    let kind: Kind
    let label: String
    let value: String

    var id: Kind { kind }
}

struct PlexPlaybackBandwidthSample: Equatable, Sendable {
    let bitsPerSecond: Double
    let measuredAt: Date
    let byteCount: Int64
    let transferDuration: TimeInterval

    init?(
        byteCount: Int64,
        responseStartTime: Date,
        responseEndTime: Date,
        wasReadFromCache: Bool,
        hadError: Bool
    ) {
        let transferDuration = responseEndTime.timeIntervalSince(responseStartTime)
        guard !wasReadFromCache,
              !hadError,
              byteCount > 0,
              transferDuration.isFinite,
              transferDuration > 0 else {
            return nil
        }

        let bitsPerSecond = (Double(byteCount) * 8) / transferDuration
        guard bitsPerSecond.isFinite, bitsPerSecond > 0 else {
            return nil
        }

        self.bitsPerSecond = bitsPerSecond
        measuredAt = responseEndTime
        self.byteCount = byteCount
        self.transferDuration = transferDuration
    }

    init?(
        resourceRequest event: AVMetricMediaResourceRequestEvent,
        fallbackByteCount: Int64? = nil
    ) {
        let transaction = event.networkTransactionMetrics?.transactionMetrics
            .reversed()
            .first { transaction in
                transaction.countOfResponseBodyBytesReceived > 0
                    && transaction.responseStartDate != nil
                    && transaction.responseEndDate != nil
            }
        if let transaction,
           let responseStartTime = transaction.responseStartDate,
           let responseEndTime = transaction.responseEndDate {
            self.init(
                byteCount: transaction.countOfResponseBodyBytesReceived,
                responseStartTime: responseStartTime,
                responseEndTime: responseEndTime,
                wasReadFromCache: event.wasReadFromCache,
                hadError: event.errorEvent != nil
            )
            return
        }

        let resourceByteCount = Int64(event.byteRange.length)
        let byteCount = (resourceByteCount > 0 ? resourceByteCount : nil)
            ?? fallbackByteCount
            ?? 0
        self.init(
            byteCount: byteCount,
            responseStartTime: event.responseStartTime,
            responseEndTime: event.responseEndTime,
            wasReadFromCache: event.wasReadFromCache,
            hadError: event.errorEvent != nil
        )
    }

    init?(segment event: AVMetricHLSMediaSegmentRequestEvent) {
        guard event.mediaType == .video,
              !event.isMapSegment,
              let resourceRequest = event.mediaResourceRequestEvent else {
            return nil
        }
        self.init(
            resourceRequest: resourceRequest,
            fallbackByteCount: Int64(event.byteRange.length)
        )
    }
}

struct PlexPlaybackVariantFacts: Equatable, Sendable {
    let videoWidth: Int?
    let videoHeight: Int?
    let averageBitRate: Double?
    let peakBitRate: Double?

    init?(variant: AVAssetVariant?) {
        guard let variant else {
            return nil
        }
        self.init(
            presentationSize: variant.videoAttributes?.presentationSize,
            averageBitRate: variant.averageBitRate,
            peakBitRate: variant.peakBitRate
        )
    }

    init?(
        presentationSize: CGSize?,
        averageBitRate: Double?,
        peakBitRate: Double?
    ) {
        let dimensions = Self.integralDimensions(presentationSize)
        let averageBitRate = Self.positiveFinite(averageBitRate)
        let peakBitRate = Self.positiveFinite(peakBitRate)
        guard dimensions != nil || averageBitRate != nil || peakBitRate != nil else {
            return nil
        }

        videoWidth = dimensions?.width
        videoHeight = dimensions?.height
        self.averageBitRate = averageBitRate
        self.peakBitRate = peakBitRate
    }

    var label: String {
        var components: [String] = []
        if let videoWidth, let videoHeight {
            components.append("\(videoWidth) × \(videoHeight)")
        }
        if let averageBitRate,
           let label = PlexPlaybackMetricFormatter.bitRate(averageBitRate) {
            components.append("\(label) average")
        }
        if let peakBitRate,
           let label = PlexPlaybackMetricFormatter.bitRate(peakBitRate) {
            components.append("\(label) peak")
        }
        return components.joined(separator: " · ")
    }

    private static func integralDimensions(_ size: CGSize?) -> (width: Int, height: Int)? {
        guard let size,
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              let width = Int(exactly: Double(size.width)),
              let height = Int(exactly: Double(size.height)) else {
            return nil
        }
        return (width, height)
    }

    private static func positiveFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }
        return value
    }
}

struct PlexPlaybackMetricFacts: Equatable, Sendable {
    private(set) var receivedEvent = false
    private(set) var initialStartupTime: TimeInterval?
    private(set) var stallCount = 0
    private(set) var successfulVariantSwitchCount = 0
    private(set) var failedVariantSwitchCount = 0
    private(set) var currentVariant: PlexPlaybackVariantFacts?
    private(set) var lastMeasuredBandwidth: PlexPlaybackBandwidthSample?

    mutating func recordInitialLikelyToKeepUp(
        timeTaken: TimeInterval,
        variant: PlexPlaybackVariantFacts?
    ) {
        receivedEvent = true
        initialStartupTime = PlexPlaybackMetricFormatter.nonnegativeFinite(timeTaken)
        currentVariant = variant
    }

    mutating func recordStall() {
        receivedEvent = true
        stallCount += 1
    }

    mutating func recordVariantSwitch(
        succeeded: Bool,
        to variant: PlexPlaybackVariantFacts?
    ) {
        receivedEvent = true
        if succeeded {
            successfulVariantSwitchCount += 1
            currentVariant = variant
        } else {
            failedVariantSwitchCount += 1
        }
    }

    mutating func recordBandwidthSample(_ sample: PlexPlaybackBandwidthSample?) {
        guard let sample else {
            return
        }
        receivedEvent = true
        lastMeasuredBandwidth = sample
    }

    var diagnosticFacts: [PlexPlaybackMetricDiagnosticFact] {
        guard receivedEvent else {
            return []
        }

        var facts: [PlexPlaybackMetricDiagnosticFact] = []
        if let initialStartupTime,
           let label = PlexPlaybackMetricFormatter.duration(initialStartupTime) {
            facts.append(.init(
                kind: .initialStartup,
                label: "Initial Startup",
                value: label
            ))
        }
        facts.append(.init(
            kind: .stalls,
            label: "Playback Stalls",
            value: stallCount.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        ))
        if successfulVariantSwitchCount > 0 {
            facts.append(.init(
                kind: .variantSwitches,
                label: "Successful Variant Switches",
                value: successfulVariantSwitchCount.formatted(
                    .number.locale(Locale(identifier: "en_US_POSIX"))
                )
            ))
        }
        if failedVariantSwitchCount > 0 {
            facts.append(.init(
                kind: .failedVariantSwitches,
                label: "Failed Variant Switches",
                value: failedVariantSwitchCount.formatted(
                    .number.locale(Locale(identifier: "en_US_POSIX"))
                )
            ))
        }
        if let currentVariant {
            facts.append(.init(
                kind: .currentVariant,
                label: "Current Variant",
                value: currentVariant.label
            ))
        }
        if let lastMeasuredBandwidth,
           let label = PlexPlaybackMetricFormatter.bitRate(
            lastMeasuredBandwidth.bitsPerSecond
           ) {
            facts.append(.init(
                kind: .measuredBandwidth,
                label: "Last Measured Bandwidth",
                value: label
            ))
        }
        return facts
    }
}

private enum PlexPlaybackMetricFormatter {
    static func nonnegativeFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else {
            return nil
        }
        return value
    }

    static func duration(_ seconds: Double?) -> String? {
        guard let seconds = nonnegativeFinite(seconds) else {
            return nil
        }
        return "\(number(seconds, maximumFractionDigits: 3)) sec"
    }

    static func bitRate(_ bitsPerSecond: Double?) -> String? {
        guard let bitsPerSecond, bitsPerSecond.isFinite, bitsPerSecond > 0 else {
            return nil
        }
        if bitsPerSecond >= 1_000_000 {
            return "\(number(bitsPerSecond / 1_000_000, maximumFractionDigits: 3)) Mbps"
        }
        if bitsPerSecond >= 1_000 {
            return "\(number(bitsPerSecond / 1_000, maximumFractionDigits: 3)) kbps"
        }
        return "\(number(bitsPerSecond, maximumFractionDigits: 0)) bps"
    }

    private static func number(_ value: Double, maximumFractionDigits: Int) -> String {
        value.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .precision(.fractionLength(0...maximumFractionDigits))
        )
    }
}
