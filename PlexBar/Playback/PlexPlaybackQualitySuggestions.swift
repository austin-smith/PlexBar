import Foundation

struct PlexPlaybackQualitySuggestion: Equatable, Identifiable, Sendable {
    enum Reason: Equatable, Sendable {
        case repeatedStalls(count: Int)
    }

    let targetQuality: PlexVideoQuality
    let reason: Reason

    var id: String {
        switch reason {
        case .repeatedStalls:
            "lower-\(targetQuality.rawValue)"
        }
    }

    var message: String {
        switch reason {
        case .repeatedStalls(let count):
            "Playback stalled \(count) times. Change to \(targetQuality.label) for this item?"
        }
    }
}

enum PlexPlaybackQualitySuggestionPolicy {
    static let requiredStallCount = 3

    static func suggestion(
        isEnabled: Bool,
        selection: PlexVideoQualitySelection,
        sourceBitrate: Int?,
        maximumQuality: PlexVideoQuality,
        metrics: PlexPlaybackMetricFacts?,
        excludedQualities: Set<PlexVideoQuality>
    ) -> PlexPlaybackQualitySuggestion? {
        guard isEnabled,
              selection.isVideo,
              selection.canChange,
              let metrics,
              metrics.stallCount >= requiredStallCount,
              let targetQuality = lowerQuality(
                than: selection.selectedQuality,
                sourceBitrate: sourceBitrate,
                maximumQuality: maximumQuality
              ),
              !excludedQualities.contains(targetQuality) else {
            return nil
        }

        return PlexPlaybackQualitySuggestion(
            targetQuality: targetQuality,
            reason: .repeatedStalls(count: metrics.stallCount)
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
}

struct PlexPlaybackQualitySuggestionSessionState: Equatable, Sendable {
    private(set) var itemKey: String?
    private(set) var isSuppressed = false
    private(set) var acceptedQualities: Set<PlexVideoQuality> = []

    mutating func beginSession(itemKey: String) {
        self.itemKey = itemKey
        isSuppressed = false
        acceptedQualities = []
    }

    mutating func moveToItem(itemKey: String) {
        guard self.itemKey != itemKey else {
            return
        }
        beginSession(itemKey: itemKey)
    }

    mutating func suppress() {
        isSuppressed = true
    }

    mutating func recordAccepted(_ quality: PlexVideoQuality) {
        acceptedQualities.insert(quality)
    }

    mutating func reset() {
        itemKey = nil
        isSuppressed = false
        acceptedQualities = []
    }
}
