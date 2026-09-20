import Foundation

extension StudioStore {
    func sourceGeneration(for job: StudioJob) -> StudioJob? {
        guard let candidateID = job.artwork?.sourceCandidateID,
              let candidate = manifest.candidates.first(where: { $0.id == candidateID }) else { return nil }
        return manifest.jobs.first { $0.id == candidate.jobID }
    }

    func revisions(of job: StudioJob) -> [StudioJob] {
        let candidates = Set(manifest.candidates.filter { $0.jobID == job.id }.map(\.id))
        return manifest.jobs.reversed().filter { revision in
            revision.artwork?.sourceCandidateID.map { candidates.contains($0) } == true
        }
    }

    func isEarlierVersion(_ job: StudioJob) -> Bool {
        job.status == .review && !revisions(of: job).isEmpty
    }

    func generationFilter(for job: StudioJob) -> StudioGenerationFilter {
        if isEarlierVersion(job) { return .history }
        return StudioGenerationFilter.category(for: job.status,
            needsPermission: generations.runtimes[job.id]?.engine.approvals.isEmpty == false)
    }

    func generationJobs(in filter: StudioGenerationFilter) -> [StudioJob] {
        manifest.jobs.reversed().filter { filter == .all || generationFilter(for: $0) == filter }
    }

    var generationAttentionCount: Int { generationJobs(in: .attention).count }

    var generationSummary: String {
        let attention = generationAttentionCount
        let progress = generationJobs(in: .inProgress)
        let running = progress.filter { $0.status == .running }.count
        let queued = progress.filter { $0.status == .queued }.count
        var parts: [String] = []
        if attention > 0 { parts.append("\(attention) \(attention == 1 ? "needs" : "need") attention") }
        if running > 0 { parts.append("\(running) running") }
        if queued > 0 { parts.append("\(queued) queued") }
        return parts.isEmpty ? "Generations" : parts.joined(separator: " · ")
    }

    func generationActionTitle(for job: StudioJob) -> String? {
        switch job.status {
        case .review: isEarlierVersion(job) ? nil : "Review"
        case .failed, .interrupted: "Retry"
        case .running where generationFilter(for: job) == .attention: "Respond"
        default: nil
        }
    }
}
