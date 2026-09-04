import Foundation

struct PlexMediaMarker: Decodable, Equatable, Hashable, Sendable {
    let id: String?
    let type: String
    let startTimeOffset: Int?
    let endTimeOffset: Int?
    let isFinal: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case startTimeOffset
        case endTimeOffset
        case isFinal = "final"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexStringIfPresent(forKey: .id)
        type = try values.decode(String.self, forKey: .type)
        startTimeOffset = values.decodePlexIntIfPresent(forKey: .startTimeOffset)
        endTimeOffset = values.decodePlexIntIfPresent(forKey: .endTimeOffset)
        isFinal = values.decodePlexBoolIfPresent(forKey: .isFinal)
    }
}

enum PlexPlaybackMarkerKind: String, Equatable, Hashable, Sendable {
    case intro
    case commercial
    case credits

    var label: String {
        switch self {
        case .intro:
            "Skip Intro"
        case .commercial:
            "Skip Ads"
        case .credits:
            "Skip Credits"
        }
    }
}

enum PlexPlaybackMarkerBehavior: String, CaseIterable, Identifiable, Sendable {
    case disabled
    case manually
    case automatically

    var id: Self { self }

    var label: String {
        switch self {
        case .disabled:
            "Disabled"
        case .manually:
            "Manually"
        case .automatically:
            "Automatically"
        }
    }
}

struct PlexPlaybackMarkerPreferences: Equatable, Sendable {
    let intro: PlexPlaybackMarkerBehavior
    let ads: PlexPlaybackMarkerBehavior
    let credits: PlexPlaybackMarkerBehavior

    func behavior(for kind: PlexPlaybackMarkerKind) -> PlexPlaybackMarkerBehavior {
        switch kind {
        case .intro:
            intro
        case .commercial:
            ads
        case .credits:
            credits
        }
    }
}

struct PlexPlaybackMarkerAction: Equatable, Identifiable, Sendable {
    let id: String
    let kind: PlexPlaybackMarkerKind
    let startTime: TimeInterval
    let targetTime: TimeInterval

    var label: String { kind.label }

    var accessibilityHint: String {
        switch kind {
        case .intro:
            "Moves playback to the end of the intro."
        case .commercial:
            "Moves playback to the end of the commercial break."
        case .credits:
            "Moves playback to the end of the credits."
        }
    }

    static func active(
        in markers: [PlexMediaMarker],
        at position: TimeInterval,
        duration: TimeInterval?
    ) -> Self? {
        guard position.isFinite, position >= 0 else {
            return nil
        }

        return markers.compactMap { marker in
            action(for: marker, duration: duration)
        }
        .filter { action in
            position >= action.startTime && position < action.targetTime
        }
        .min { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            return lhs.id < rhs.id
        }
    }

    static func manual(
        in markers: [PlexMediaMarker],
        at position: TimeInterval,
        duration: TimeInterval?,
        preferences: PlexPlaybackMarkerPreferences
    ) -> Self? {
        guard let action = active(in: markers, at: position, duration: duration),
              preferences.behavior(for: action.kind) == .manually else {
            return nil
        }
        return action
    }

    static func creditsStartTime(
        in markers: [PlexMediaMarker],
        duration: TimeInterval?
    ) -> TimeInterval? {
        markers.compactMap { marker in
            guard let action = action(for: marker, duration: duration),
                  action.kind == .credits else {
                return nil
            }
            return action.startTime
        }
        .min()
    }

    private static func action(
        for marker: PlexMediaMarker,
        duration: TimeInterval?
    ) -> Self? {
        let kind: PlexPlaybackMarkerKind
        switch marker.type.lowercased() {
        case "intro":
            kind = .intro
        case "commercial":
            kind = .commercial
        case "credit", "credits":
            kind = .credits
        default:
            return nil
        }

        guard let startOffset = marker.startTimeOffset,
              let endOffset = marker.endTimeOffset,
              startOffset >= 0,
              endOffset > startOffset else {
            return nil
        }

        let startTime = TimeInterval(startOffset) / 1_000
        var targetTime = TimeInterval(endOffset) / 1_000
        if let duration, duration.isFinite, duration > 0 {
            targetTime = min(targetTime, duration)
        }
        guard targetTime > startTime else {
            return nil
        }

        return Self(
            id: marker.id ?? "\(kind.rawValue):\(startOffset):\(endOffset)",
            kind: kind,
            startTime: startTime,
            targetTime: targetTime
        )
    }
}

struct PlexAutomaticPlaybackMarkerTransition: Equatable, Sendable {
    private(set) var enteredAction: PlexPlaybackMarkerAction?

    mutating func action(
        for activeAction: PlexPlaybackMarkerAction?,
        preferences: PlexPlaybackMarkerPreferences
    ) -> PlexPlaybackMarkerAction? {
        guard let activeAction,
              preferences.behavior(for: activeAction.kind) == .automatically else {
            enteredAction = nil
            return nil
        }

        guard enteredAction != activeAction else {
            return nil
        }
        enteredAction = activeAction
        return activeAction
    }

    mutating func retry(_ action: PlexPlaybackMarkerAction) {
        guard enteredAction == action else {
            return
        }
        enteredAction = nil
    }

    mutating func reset() {
        enteredAction = nil
    }
}
