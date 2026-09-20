import Foundation

public struct PlexTimelineReportCadence {
    public static let defaultReportingInterval: Duration = .seconds(10)

    public let reportingInterval: Duration
    public private(set) var lastReportedState: PlexTimelineState?
    public private(set) var lastReportInstant: ContinuousClock.Instant?

    public init(reportingInterval: Duration = Self.defaultReportingInterval) {
        self.reportingInterval = reportingInterval
    }

    public func shouldReport(
        state: PlexTimelineState,
        at instant: ContinuousClock.Instant
    ) -> Bool {
        guard let lastReportedState, let lastReportInstant else {
            return true
        }
        return state != lastReportedState
            || lastReportInstant.duration(to: instant) >= reportingInterval
    }

    public mutating func record(
        state: PlexTimelineState,
        at instant: ContinuousClock.Instant
    ) {
        lastReportedState = state
        lastReportInstant = instant
    }

    public mutating func reset() {
        lastReportedState = nil
        lastReportInstant = nil
    }
}

@MainActor
public final class PlexTimelineReportSequencer {
    public typealias ReportOperation = @MainActor (PlexTimelineUpdate) async -> PlexTimelineResponse?

    private let reportOperation: ReportOperation
    private var tail: Task<PlexTimelineResponse?, Never>?

    public init(reportOperation: @escaping ReportOperation) {
        self.reportOperation = reportOperation
    }

    public func report(_ update: PlexTimelineUpdate) async -> PlexTimelineResponse? {
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
