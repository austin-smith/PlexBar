import Foundation

struct PlexRewindOnResume: Equatable, Sendable {
    static let secondsRange = 0...30
    static let none = PlexRewindOnResume(seconds: 0)

    let seconds: Int

    init(seconds: Int) {
        self.seconds = min(max(seconds, Self.secondsRange.lowerBound), Self.secondsRange.upperBound)
    }

    var label: String {
        switch seconds {
        case 0:
            "None"
        case 1:
            "1 Second"
        default:
            "\(seconds) Seconds"
        }
    }

    func target(from position: TimeInterval) -> TimeInterval? {
        guard seconds > 0, position.isFinite, position > 0 else {
            return nil
        }
        return max(position - TimeInterval(seconds), 0)
    }
}

enum PlexRewindOnResumeAction: Equatable, Sendable {
    case playImmediately
    case seekThenPlay(target: TimeInterval)
}

enum PlexRewindOnResumePolicy {
    static func action(
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

    static func transportAction(
        status: PlexPlaybackStatus,
        hasPendingRewind: Bool
    ) -> PlexPlaybackTransportAction? {
        hasPendingRewind ? .pause : PlexPlaybackTransportAction(status: status)
    }
}
