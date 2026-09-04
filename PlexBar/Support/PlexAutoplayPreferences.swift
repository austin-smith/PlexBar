import AppKit
import Foundation

enum PlexCinemaPreplayPreference: Int, CaseIterable, Identifiable, Sendable {
    case off = -1
    case preRollOnly = 0
    case oneTrailer = 1
    case twoTrailers = 2
    case threeTrailers = 3
    case fourTrailers = 4
    case fiveTrailers = 5

    var id: Self { self }

    var label: String {
        switch self {
        case .off: "Off"
        case .preRollOnly: "Pre-roll Only"
        case .oneTrailer: "1 Trailer"
        case .twoTrailers: "2 Trailers"
        case .threeTrailers: "3 Trailers"
        case .fourTrailers: "4 Trailers"
        case .fiveTrailers: "5 Trailers"
        }
    }

    /// `nil` omits the PMS parameter and therefore disables both trailers and
    /// the configured server pre-roll. Zero is intentionally distinct: PMS
    /// returns the pre-roll without prepending a trailer.
    var extrasPrefixCount: Int? {
        self == .off ? nil : rawValue
    }
}

enum PlexAutoplayCountdown: Int, CaseIterable, Identifiable, Sendable {
    case immediate = 0
    case fiveSeconds = 5
    case tenSeconds = 10
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case sixtySeconds = 60

    var id: Self { self }

    var label: String {
        switch self {
        case .immediate: "Immediately"
        case .fiveSeconds: "5 Seconds"
        case .tenSeconds: "10 Seconds"
        case .fifteenSeconds: "15 Seconds"
        case .thirtySeconds: "30 Seconds"
        case .sixtySeconds: "60 Seconds"
        }
    }
}

enum PlexPassoutProtection: Int, CaseIterable, Identifiable, Sendable {
    case never = 0
    case oneHour = 3_600
    case twoHours = 7_200
    case threeHours = 10_800

    var id: Self { self }

    var label: String {
        switch self {
        case .never: "Never"
        case .oneHour: "1 Hour"
        case .twoHours: "2 Hours"
        case .threeHours: "3 Hours"
        }
    }

    var interval: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue)
    }
}

struct PlexAutoplayPreferences: Equatable, Sendable {
    let isEnabled: Bool
    let countdown: PlexAutoplayCountdown
    let passoutProtection: PlexPassoutProtection
}

@MainActor
final class PlexUserInteractionStore {
    private(set) var lastInteractionDate: Date

    init(lastInteractionDate: Date = Date()) {
        self.lastInteractionDate = lastInteractionDate
    }

    func recordInteraction(at date: Date = Date()) {
        lastInteractionDate = date
    }
}

@MainActor
final class PlexUserInteractionMonitor {
    nonisolated(unsafe) private var eventMonitor: Any?

    init(store: PlexUserInteractionStore) {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .keyDown,
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
                .scrollWheel,
                .gesture,
                .magnify,
                .swipe,
                .rotate,
                .beginGesture,
                .endGesture,
            ]
        ) { [weak store] event in
            store?.recordInteraction()
            return event
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
