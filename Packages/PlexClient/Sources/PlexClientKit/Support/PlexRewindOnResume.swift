import Foundation

public struct PlexRewindOnResume: Equatable, Sendable {
    public static let secondsRange = 0...30
    public static let none = PlexRewindOnResume(seconds: 0)

    public let seconds: Int

    public init(seconds: Int) {
        self.seconds = min(max(seconds, Self.secondsRange.lowerBound), Self.secondsRange.upperBound)
    }

    public var label: String {
        switch seconds {
        case 0:
            "None"
        case 1:
            "1 Second"
        default:
            "\(seconds) Seconds"
        }
    }

    public func target(from position: TimeInterval) -> TimeInterval? {
        guard seconds > 0, position.isFinite, position > 0 else {
            return nil
        }
        return max(position - TimeInterval(seconds), 0)
    }
}

public enum PlexRewindOnResumeAction: Equatable, Sendable {
    case playImmediately
    case seekThenPlay(target: TimeInterval)
}

public enum PlexRewindOnResumePolicy {
    public static func action(
        status: PlexPlaybackStatus,
        position: TimeInterval,
        preference: PlexRewindOnResume
    ) -> PlexRewindOnResumeAction? {
        guard status == .paused else {
            return nil
        }
        guard let target = preference.target(from: position) else {
            return .playImmediately
        }
        return .seekThenPlay(target: target)
    }

    public static func transportAction(
        status: PlexPlaybackStatus,
        hasPendingRewind: Bool
    ) -> PlexPlaybackTransportAction? {
        hasPendingRewind ? .pause : PlexPlaybackTransportAction(status: status)
    }

    public static func shouldInterceptNativePlayPausePress(
        status: PlexPlaybackStatus,
        hasPendingRewind: Bool,
        isPlaybackControlBusy: Bool,
        preference: PlexRewindOnResume
    ) -> Bool {
        if hasPendingRewind || isPlaybackControlBusy {
            return true
        }
        return status == .paused && preference.seconds > 0
    }
}
