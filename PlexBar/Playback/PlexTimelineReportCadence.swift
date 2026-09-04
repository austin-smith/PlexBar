import Foundation

struct PlexTimelineReportCadence {
    static let defaultReportingInterval: Duration = .seconds(10)

    let reportingInterval: Duration
    private(set) var lastReportedState: PlexTimelineState?
    private(set) var lastReportInstant: ContinuousClock.Instant?

    init(reportingInterval: Duration = Self.defaultReportingInterval) {
        self.reportingInterval = reportingInterval
    }

    func shouldReport(
        state: PlexTimelineState,
        at instant: ContinuousClock.Instant
    ) -> Bool {
        guard let lastReportedState, let lastReportInstant else {
            return true
        }
        return state != lastReportedState
            || lastReportInstant.duration(to: instant) >= reportingInterval
    }

    mutating func record(
        state: PlexTimelineState,
        at instant: ContinuousClock.Instant
    ) {
        lastReportedState = state
        lastReportInstant = instant
    }

    mutating func reset() {
        lastReportedState = nil
        lastReportInstant = nil
    }
}

@MainActor
final class PlexTimelineReportSequencer {
    typealias ReportOperation = @MainActor (PlexTimelineUpdate) async -> PlexTimelineResponse?

    private let reportOperation: ReportOperation
    private var tail: Task<PlexTimelineResponse?, Never>?

    init(reportOperation: @escaping ReportOperation) {
        self.reportOperation = reportOperation
    }

    func report(_ update: PlexTimelineUpdate) async -> PlexTimelineResponse? {
        let previous = tail
        let reportOperation = reportOperation
        let task = Task { @MainActor in
            if let previous {
                _ = await previous.value
            }
            return await reportOperation(update)
        }
        tail = task
        return await task.value
    }
}
