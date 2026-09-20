import SwiftUI

struct StudioGenerationRow: View {
    let store: StudioStore
    let job: StudioJob

    private var runtime: StudioGenerationRuntime? { store.generations.runtimes[job.id] }
    private var thumbnail: URL? {
        guard let history = store.historyURL else { return nil }
        if let candidate = store.manifest.candidates.first(where: { $0.jobID == job.id }) {
            return try? StudioFiles.resolved(candidate.file, in: history)
        }
        guard let reference = job.artwork?.references.first else { return nil }
        return try? StudioFiles.resolved(job.directory + "/" + reference, in: history)
    }
    private var status: String {
        if runtime?.isStopping == true { return "Stopping…" }
        if runtime?.engine.approvals.isEmpty == false { return "Needs permission" }
        switch job.status {
        case .queued: return "Queued"
        case .running: return "Generating…"
        case .review: return store.isEarlierVersion(job) ? "Earlier version" : "Ready to review"
        case .accepted: return "Accepted"
        case .rejected: return "Discarded"
        case .failed: return "Failed"
        case .interrupted: return "Interrupted"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            StudioImageView(url: thumbnail).frame(width: 42, height: 52).clipShape(.rect(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 5) {
                Text(job.title).font(.headline).lineLimit(2)
                Text(job.artwork?.role.title ?? "Catalog").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    if job.status == .running { ProgressView().controlSize(.mini).accessibilityHidden(true) }
                    Text(status).font(.caption)
                }
                .foregroundStyle(job.status == .failed || runtime?.engine.approvals.isEmpty == false ? Color.orange : Color.secondary)
            }
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}
