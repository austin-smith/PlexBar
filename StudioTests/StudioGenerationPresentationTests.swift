import Foundation
import Testing
@testable import PlexBarStudio

@Suite @MainActor struct StudioGenerationPresentationTests {
    private func job(_ status: StudioJob.Status) -> StudioJob {
        var job = StudioJob(id: UUID(), title: status.rawValue, kind: .artwork, prompt: "Test", createdAt: Date())
        job.status = status
        return job
    }

    @Test func filtersSeparateActionableWorkFromProgressAndHistory() {
        let expected: [(StudioJob.Status, StudioGenerationFilter)] = [
            (.queued, .inProgress), (.running, .inProgress), (.review, .attention),
            (.failed, .attention), (.interrupted, .attention), (.accepted, .history), (.rejected, .history)
        ]
        for (status, filter) in expected {
            #expect(StudioGenerationFilter.category(for: status, needsPermission: false) == filter)
        }
        #expect(StudioGenerationFilter.category(for: .running, needsPermission: true) == .attention)
        // A stale approval cannot make a completed generation actionable again.
        #expect(StudioGenerationFilter.category(for: .accepted, needsPermission: true) == .history)
    }

    @Test func toolbarCountsAndActionsMatchTheFilters() {
        let store = StudioStore()
        store.manifest.jobs = [.review, .failed, .interrupted, .running, .running, .queued, .accepted, .rejected].map(job)
        #expect(store.generationAttentionCount == 3)
        #expect(store.generationJobs(in: .inProgress).count == 3)
        #expect(store.generationJobs(in: .history).count == 2)
        #expect(store.generationSummary == "3 need attention · 2 running · 1 queued")
        #expect(store.generationActionTitle(for: job(.review)) == "Review")
        #expect(store.generationActionTitle(for: job(.failed)) == "Retry")
        #expect(store.generationActionTitle(for: job(.interrupted)) == "Retry")
        #expect(store.generationActionTitle(for: job(.accepted)) == nil)
        #expect(store.generationActionTitle(for: job(.queued)) == nil)
        store.manifest.jobs = [job(.review)]
        #expect(store.generationSummary == "1 needs attention")
        store.manifest.jobs = [job(.accepted)]
        #expect(store.generationSummary == "Generations")
    }

    @Test func permissionRequestsMoveBetweenFiltersWithoutDoubleCounting() async {
        let store = StudioStore()
        let running = job(.running)
        store.manifest.jobs = [running]
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        store.generations.start(id: running.id, operation: { _ in
            for await _ in stream { break }
        }, didFinish: {})
        let engine = store.generations.runtimes[running.id]!.engine
        engine.approvals = [.init(rpcID: .integer(1), method: "test", details: "Test permission")]
        #expect(store.generationJobs(in: .attention).map(\.id) == [running.id])
        #expect(store.generationJobs(in: .inProgress).isEmpty)
        #expect(store.generationSummary == "1 needs attention")
        #expect(store.generationActionTitle(for: running) == "Respond")
        engine.approvals.removeAll()
        #expect(store.generationJobs(in: .attention).isEmpty)
        #expect(store.generationJobs(in: .inProgress).map(\.id) == [running.id])
        #expect(store.generationSummary == "1 running")
        continuation.finish()
        await store.generations.shutdown()
    }

    @Test func selectionStaysOpenAfterReviewRetryAndBackgroundCompletion() {
        let selected = UUID(), other = UUID(), arriving = UUID()
        var selection = StudioGenerationSelection()
        #expect(selection.filter == .attention)
        selection.reconcile(allIDs: [selected, other], matchingIDs: [selected])
        #expect(selection.jobID == selected)
        // Accept/retry moves the row away, while another attention item arrives.
        selection.reconcile(allIDs: [selected, other, arriving], matchingIDs: [arriving])
        #expect(selection.jobID == selected)
        selection.changeFilter(to: .inProgress, matchingIDs: [other])
        #expect(selection.jobID == other)
        // The selected running job finishes; its review remains open.
        selection.reconcile(allIDs: [selected, other, arriving], matchingIDs: [])
        #expect(selection.jobID == other)
        selection.changeFilter(to: .history, matchingIDs: [])
        #expect(selection.jobID == nil)
        selection.reconcile(allIDs: [selected, arriving], matchingIDs: [selected])
        #expect(selection.jobID == selected)
        selection.reconcile(allIDs: [arriving], matchingIDs: [arriving])
        #expect(selection.jobID == arriving)
    }
}
