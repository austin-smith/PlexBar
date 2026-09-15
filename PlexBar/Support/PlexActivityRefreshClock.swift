import Foundation

struct PlexActivityRefreshClock: Sendable {
    var now: @Sendable () -> ContinuousClock.Instant
    var sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void

    static let continuous = PlexActivityRefreshClock(
        now: { ContinuousClock.now },
        sleepUntil: { deadline in
            try await ContinuousClock().sleep(until: deadline, tolerance: .seconds(1))
        }
    )
}
