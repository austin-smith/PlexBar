import Foundation

public enum PlexPlaybackSleepTimerPreset: String, CaseIterable, Identifiable, Sendable {
    case off
    case fifteenMinutes
    case thirtyMinutes
    case fortyFiveMinutes
    case oneHour
    case endOfItem

    public var id: Self { self }

    public var label: String {
        switch self {
        case .off: "Off"
        case .fifteenMinutes: "15 Minutes"
        case .thirtyMinutes: "30 Minutes"
        case .fortyFiveMinutes: "45 Minutes"
        case .oneHour: "1 Hour"
        case .endOfItem: "End of Current Item"
        }
    }

    fileprivate var duration: TimeInterval? {
        switch self {
        case .off, .endOfItem: nil
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .fortyFiveMinutes: 45 * 60
        case .oneHour: 60 * 60
        }
    }
}

public struct PlexPlaybackSleepTimer: Equatable, Sendable {
    public static let off = Self(preset: .off)

    public let preset: PlexPlaybackSleepTimerPreset
    public let deadline: Date?

    public init(
        preset: PlexPlaybackSleepTimerPreset,
        startingAt date: Date = .now
    ) {
        self.preset = preset
        deadline = preset.duration.map { date.addingTimeInterval($0) }
    }

    public var isActive: Bool {
        preset != .off
    }

    public var stopsAtEndOfItem: Bool {
        preset == .endOfItem
    }

    public func remainingTime(at date: Date = .now) -> TimeInterval? {
        deadline.map { max($0.timeIntervalSince(date), 0) }
    }

    public func hasExpired(at date: Date = .now) -> Bool {
        guard let deadline else { return false }
        return deadline <= date
    }
}
