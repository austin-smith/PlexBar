import AVFoundation

public enum PlexPlaybackStatus: Equatable, Sendable {
    case idle
    case preparing
    case playing
    case paused
    case buffering
    case ended
    case failed(String)
}

public enum PlexPlaybackTransportAction: Equatable, Sendable {
    case play
    case pause

    public init?(status: PlexPlaybackStatus) {
        switch status {
        case .preparing, .playing, .buffering:
            self = .pause
        case .paused:
            self = .play
        case .idle, .ended, .failed:
            return nil
        }
    }
}

public enum PlexPlaybackWaitingReason: Equatable, Sendable {
    case minimizingStalls
    case evaluatingBufferingRate
    case noItemToPlay
    case coordinatedPlayback
    case interstitialEvent

    public init?(
        timeControlStatus: AVPlayer.TimeControlStatus,
        nativeReason: AVPlayer.WaitingReason?
    ) {
        guard timeControlStatus == .waitingToPlayAtSpecifiedRate,
              let nativeReason else {
            return nil
        }

        if nativeReason == .toMinimizeStalls {
            self = .minimizingStalls
        } else if nativeReason == .evaluatingBufferingRate {
            self = .evaluatingBufferingRate
        } else if nativeReason == .noItemToPlay {
            self = .noItemToPlay
        } else if nativeReason == .waitingForCoordinatedPlayback {
            self = .coordinatedPlayback
        } else if nativeReason == .interstitialEvent {
            self = .interstitialEvent
        } else {
            return nil
        }
    }

    public var diagnosticLabel: String? {
        switch self {
        case .minimizingStalls:
            "Minimizing Stalls"
        case .evaluatingBufferingRate:
            nil
        case .noItemToPlay:
            "No Item to Play"
        case .coordinatedPlayback:
            "Coordinated Playback"
        case .interstitialEvent:
            "Interstitial Event"
        }
    }
}
