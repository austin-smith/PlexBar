import AVFoundation
import CoreGraphics
import Foundation

public struct PlexPlaybackMetricDiagnosticFact: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case initialStartup
        case stalls
        case variantSwitches
        case failedVariantSwitches
        case currentVariant
        case measuredBandwidth
    }

    public let kind: Kind
    public let label: String
    public let value: String

    public var id: Kind { kind }

    public init(kind: Kind, label: String, value: String) {
        self.kind = kind
        self.label = label
        self.value = value
    }
}

public struct PlexPlaybackBandwidthSample: Equatable, Sendable {
    public let bitsPerSecond: Double
    public let measuredAt: Date
    public let byteCount: Int64
    public let transferDuration: TimeInterval

    public init?(
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

    public init?(
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

    public init?(segment event: AVMetricHLSMediaSegmentRequestEvent) {
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

public struct PlexPlaybackVariantFacts: Equatable, Sendable {
    public let videoWidth: Int?
    public let videoHeight: Int?
    public let averageBitRate: Double?
    public let peakBitRate: Double?

    public init?(variant: AVAssetVariant?) {
        guard let variant else {
            return nil
        }
        self.init(
            presentationSize: variant.videoAttributes?.presentationSize,
            averageBitRate: variant.averageBitRate,
            peakBitRate: variant.peakBitRate
        )
    }

    public init?(
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

    public var label: String {
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

public struct PlexPlaybackMetricFacts: Equatable, Sendable {
    public private(set) var receivedEvent = false
    public private(set) var initialStartupTime: TimeInterval?
    public private(set) var stallCount = 0
    public private(set) var successfulVariantSwitchCount = 0
    public private(set) var failedVariantSwitchCount = 0
    public private(set) var currentVariant: PlexPlaybackVariantFacts?
    public private(set) var previousMeasuredBandwidth: PlexPlaybackBandwidthSample?
    public private(set) var lastMeasuredBandwidth: PlexPlaybackBandwidthSample?

    public mutating func recordInitialLikelyToKeepUp(
        timeTaken: TimeInterval,
        variant: PlexPlaybackVariantFacts?
    ) {
        receivedEvent = true
        initialStartupTime = PlexPlaybackMetricFormatter.nonnegativeFinite(timeTaken)
        currentVariant = variant
    }

    public mutating func recordStall() {
        receivedEvent = true
        stallCount += 1
    }

    public mutating func recordVariantSwitch(
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

    public mutating func recordBandwidthSample(_ sample: PlexPlaybackBandwidthSample?) {
        guard let sample else {
            return
        }
        receivedEvent = true
        previousMeasuredBandwidth = lastMeasuredBandwidth
        lastMeasuredBandwidth = sample
    }

    public var diagnosticFacts: [PlexPlaybackMetricDiagnosticFact] {
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

    public init(
        receivedEvent: Bool = false,
        initialStartupTime: TimeInterval? = nil,
        stallCount: Int = 0,
        successfulVariantSwitchCount: Int = 0,
        failedVariantSwitchCount: Int = 0,
        currentVariant: PlexPlaybackVariantFacts? = nil,
        previousMeasuredBandwidth: PlexPlaybackBandwidthSample? = nil,
        lastMeasuredBandwidth: PlexPlaybackBandwidthSample? = nil
    ) {
        self.receivedEvent = receivedEvent
        self.initialStartupTime = initialStartupTime
        self.stallCount = stallCount
        self.successfulVariantSwitchCount = successfulVariantSwitchCount
        self.failedVariantSwitchCount = failedVariantSwitchCount
        self.currentVariant = currentVariant
        self.previousMeasuredBandwidth = previousMeasuredBandwidth
        self.lastMeasuredBandwidth = lastMeasuredBandwidth
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
