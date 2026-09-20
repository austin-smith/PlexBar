import Foundation

public struct PlexPlaybackQualitySuggestion: Equatable, Identifiable, Sendable {
    public enum Reason: Equatable, Sendable {
        case repeatedStalls(count: Int)
        case improvedBandwidth
    }

    public let targetQuality: PlexVideoQuality
    public let reason: Reason

    public var id: String {
        switch reason {
        case .repeatedStalls:
            "lower-\(targetQuality.rawValue)"
        case .improvedBandwidth:
            "higher-\(targetQuality.rawValue)"
        }
    }

    public var message: String {
        switch reason {
        case .repeatedStalls(let count):
            "Playback stalled \(count) times. Change to \(targetQuality.label) for this item?"
        case .improvedBandwidth:
            "Playback bandwidth increased. Change to \(targetQuality.label) for this item?"
        }
    }

    public init(targetQuality: PlexVideoQuality, reason: Reason) {
        self.targetQuality = targetQuality
        self.reason = reason
    }
}

public enum PlexPlaybackQualitySuggestionPolicy {
    public static let requiredStallCount = 3

    public static func suggestion(
        isEnabled: Bool,
        selection: PlexVideoQualitySelection,
        sourceBitrate: Int?,
        maximumQuality: PlexVideoQuality,
        isTranscoding: Bool,
        metrics: PlexPlaybackMetricFacts?,
        excludedQualities: Set<PlexVideoQuality>
    ) -> PlexPlaybackQualitySuggestion? {
        guard isEnabled,
              selection.isVideo,
              selection.canChange,
              let metrics else {
            return nil
        }

        if metrics.stallCount >= requiredStallCount,
           let targetQuality = lowerQuality(
                than: selection.selectedQuality,
                sourceBitrate: sourceBitrate,
                maximumQuality: maximumQuality
           ),
           !excludedQualities.contains(targetQuality) {
            return PlexPlaybackQualitySuggestion(
                targetQuality: targetQuality,
                reason: .repeatedStalls(count: metrics.stallCount)
            )
        }

        guard isTranscoding,
              let targetQuality = higherQuality(
                than: selection.selectedQuality,
                sourceBitrate: sourceBitrate,
                maximumQuality: maximumQuality,
                previousBandwidth: metrics.previousMeasuredBandwidth,
                measuredBandwidth: metrics.lastMeasuredBandwidth
              ),
              !excludedQualities.contains(targetQuality) else {
            return nil
        }
        return PlexPlaybackQualitySuggestion(
            targetQuality: targetQuality,
            reason: .improvedBandwidth
        )
    }

    private static func lowerQuality(
        than selectedQuality: PlexVideoQuality,
        sourceBitrate: Int?,
        maximumQuality: PlexVideoQuality
    ) -> PlexVideoQuality? {
        let currentBitrate: Int
        if let selectedBitrate = selectedQuality.constraints?.bitrate {
            currentBitrate = selectedBitrate
        } else if let sourceBitrate, sourceBitrate > 0 {
            currentBitrate = sourceBitrate
        } else {
            return nil
        }

        let maximumBitrate = maximumQuality.constraints?.bitrate
        return PlexVideoQuality.allCases
            .compactMap { quality -> (quality: PlexVideoQuality, bitrate: Int)? in
                guard let bitrate = quality.constraints?.bitrate,
                      bitrate < currentBitrate,
                      maximumBitrate.map({ bitrate <= $0 }) ?? true else {
                    return nil
                }
                return (quality, bitrate)
            }
            .max(by: { $0.bitrate < $1.bitrate })?
            .quality
    }

    private static func higherQuality(
        than selectedQuality: PlexVideoQuality,
        sourceBitrate: Int?,
        maximumQuality: PlexVideoQuality,
        previousBandwidth: PlexPlaybackBandwidthSample?,
        measuredBandwidth: PlexPlaybackBandwidthSample?
    ) -> PlexVideoQuality? {
        guard selectedQuality != .original,
              let currentBitrate = selectedQuality.constraints?.bitrate,
              let sourceBitrate,
              sourceBitrate > currentBitrate,
              let previousBandwidth,
              let measuredBandwidth,
              measuredBandwidth.bitsPerSecond > previousBandwidth.bitsPerSecond else {
            return nil
        }

        let availableBitrate = measuredBandwidth.bitsPerSecond / 1_000
        let maximumBitrate = maximumQuality.constraints?.bitrate
        if maximumQuality == .original,
           Double(sourceBitrate) <= availableBitrate {
            return .original
        }

        return PlexVideoQuality.allCases.compactMap {
            quality -> (quality: PlexVideoQuality, bitrate: Int)? in
            guard let bitrate = quality.constraints?.bitrate,
                  bitrate > currentBitrate,
                  bitrate <= sourceBitrate,
                  Double(bitrate) <= availableBitrate,
                  maximumBitrate.map({ bitrate <= $0 }) ?? true else {
                return nil
            }
            return (quality, bitrate)
        }
        .max(by: { $0.bitrate < $1.bitrate })?
        .quality
    }
}

public struct PlexPlaybackQualitySuggestionSessionState: Equatable, Sendable {
    public private(set) var itemKey: String?
    public private(set) var isSuppressed = false
    public private(set) var acceptedQualities: Set<PlexVideoQuality> = []

    public mutating func beginSession(itemKey: String) {
        self.itemKey = itemKey
        isSuppressed = false
        acceptedQualities = []
    }

    public mutating func moveToItem(itemKey: String) {
        guard self.itemKey != itemKey else {
            return
        }
        beginSession(itemKey: itemKey)
    }

    public mutating func suppress() {
        isSuppressed = true
    }

    public mutating func recordAccepted(_ quality: PlexVideoQuality) {
        acceptedQualities.insert(quality)
    }

    public mutating func reset() {
        itemKey = nil
        isSuppressed = false
        acceptedQualities = []
    }

    public init(
        itemKey: String? = nil,
        isSuppressed: Bool = false,
        acceptedQualities: Set<PlexVideoQuality> = []
    ) {
        self.itemKey = itemKey
        self.isSuppressed = isSuppressed
        self.acceptedQualities = acceptedQualities
    }
}
