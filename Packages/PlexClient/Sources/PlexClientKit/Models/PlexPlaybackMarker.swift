import PlexModels
import Foundation

public enum PlexPlaybackMarkerKind: String, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case intro
    case commercial
    case credits

    public var id: Self { self }

    public var label: String {
        switch self {
        case .intro:
            "Skip Intro"
        case .commercial:
            "Skip Ads"
        case .credits:
            "Skip Credits"
        }
    }

    public var settingsLabel: String {
        switch self {
        case .intro:
            "Intros"
        case .commercial:
            "Ads"
        case .credits:
            "Credits"
        }
    }
}

public enum PlexPlaybackMarkerBehavior: String, CaseIterable, Identifiable, Sendable {
    case disabled
    case manually
    case automatically

    public var id: Self { self }

    public var label: String {
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

public struct PlexPlaybackMarkerPreferences: Equatable, Sendable {
    public let intro: PlexPlaybackMarkerBehavior
    public let ads: PlexPlaybackMarkerBehavior
    public let credits: PlexPlaybackMarkerBehavior

    public func behavior(for kind: PlexPlaybackMarkerKind) -> PlexPlaybackMarkerBehavior {
        switch kind {
        case .intro:
            intro
        case .commercial:
            ads
        case .credits:
            credits
        }
    }

    public init(
        intro: PlexPlaybackMarkerBehavior,
        ads: PlexPlaybackMarkerBehavior,
        credits: PlexPlaybackMarkerBehavior
    ) {
        self.intro = intro
        self.ads = ads
        self.credits = credits
    }
}

public struct PlexPlaybackMarkerAction: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: PlexPlaybackMarkerKind
    public let startTime: TimeInterval
    public let targetTime: TimeInterval

    public var label: String { kind.label }

    public var accessibilityHint: String {
        switch kind {
        case .intro:
            "Moves playback to the end of the intro."
        case .commercial:
            "Moves playback to the end of the commercial break."
        case .credits:
            "Moves playback to the end of the credits."
        }
    }

    public static func active(
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

    public static func actions(
        in markers: [PlexMediaMarker],
        duration: TimeInterval?
    ) -> [Self] {
        markers.compactMap { marker in
            action(for: marker, duration: duration)
        }
        .sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            return lhs.id < rhs.id
        }
    }

    public static func availableKinds(
        in markers: [PlexMediaMarker],
        duration: TimeInterval?
    ) -> [PlexPlaybackMarkerKind] {
        let availableKinds = Set(actions(in: markers, duration: duration).map(\.kind))
        return PlexPlaybackMarkerKind.allCases.filter(availableKinds.contains)
    }

    public static func manual(
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

    public static func creditsStartTime(
        in markers: [PlexMediaMarker],
        duration: TimeInterval?
    ) -> TimeInterval? {
        actions(in: markers, duration: duration).compactMap { action in
            action.kind == .credits ? action.startTime : nil
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

    public init(id: String, kind: PlexPlaybackMarkerKind, startTime: TimeInterval, targetTime: TimeInterval) {
        self.id = id
        self.kind = kind
        self.startTime = startTime
        self.targetTime = targetTime
    }
}

public struct PlexPlaybackInterstitial: Equatable, Sendable {
    public let startTime: TimeInterval
    public let duration: TimeInterval

    public static func commercials(
        in markers: [PlexMediaMarker],
        duration mediaDuration: TimeInterval?
    ) -> [Self] {
        let commercialActions = PlexPlaybackMarkerAction.actions(
            in: markers,
            duration: mediaDuration
        ).filter { $0.kind == .commercial }

        return commercialActions.reduce(into: [Self]()) { ranges, action in
            guard let previous = ranges.last else {
                ranges.append(Self(
                    startTime: action.startTime,
                    duration: action.targetTime - action.startTime
                ))
                return
            }

            let previousEnd = previous.startTime + previous.duration
            guard action.startTime <= previousEnd else {
                ranges.append(Self(
                    startTime: action.startTime,
                    duration: action.targetTime - action.startTime
                ))
                return
            }

            let mergedEnd = max(previousEnd, action.targetTime)
            ranges[ranges.count - 1] = Self(
                startTime: previous.startTime,
                duration: mergedEnd - previous.startTime
            )
        }
    }

    public init(startTime: TimeInterval, duration: TimeInterval) {
        self.startTime = startTime
        self.duration = duration
    }
}

public struct PlexAutomaticPlaybackMarkerTransition: Equatable, Sendable {
    public private(set) var enteredAction: PlexPlaybackMarkerAction?

    public mutating func action(
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

    public mutating func retry(_ action: PlexPlaybackMarkerAction) {
        guard enteredAction == action else {
            return
        }
        enteredAction = nil
    }

    public mutating func reset() {
        enteredAction = nil
    }

    public init(enteredAction: PlexPlaybackMarkerAction? = nil) {
        self.enteredAction = enteredAction
    }
}
