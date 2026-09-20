import Foundation
import Observation

/// Owns job lifetimes independently of the views displaying them.
@Observable @MainActor
final class StudioGenerationCoordinator {
    static let concurrencyLimit = 6
    private(set) var runtimes: [UUID: StudioGenerationRuntime] = [:]
    private(set) var isShuttingDown = false
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    var hasCapacity: Bool { !isShuttingDown && runtimes.count < Self.concurrencyLimit }

    func start(id: UUID, operation: @escaping @MainActor (StudioCodexEngine) async -> Void,
               didFinish: @escaping @MainActor () -> Void) {
        guard hasCapacity, runtimes[id] == nil else { return }
        let runtime = StudioGenerationRuntime()
        runtimes[id] = runtime
        tasks[id] = Task {
            await operation(runtime.engine)
            runtimes[id] = nil
            tasks[id] = nil
            didFinish()
        }
    }

    func stop(id: UUID) {
        runtimes[id]?.isStopping = true
        tasks[id]?.cancel()
    }

    func shutdown() async {
        isShuttingDown = true
        let pending = Array(tasks.values)
        for id in runtimes.keys { stop(id: id) }
        for task in pending { await task.value }
    }
}

@Observable @MainActor
final class StudioGenerationRuntime {
    let engine = StudioCodexEngine()
    var isStopping = false
}
