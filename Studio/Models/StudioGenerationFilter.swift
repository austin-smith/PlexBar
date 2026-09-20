import Foundation

enum StudioGenerationFilter: String, CaseIterable, Identifiable {
    case attention, inProgress, history, all

    var id: Self { self }
    var title: String {
        switch self {
        case .attention: "Needs Attention"
        case .inProgress: "In Progress"
        case .history: "History"
        case .all: "All"
        }
    }
    var emptyMessage: String {
        switch self {
        case .attention: "Nothing needs attention"
        case .inProgress: "No generations in progress"
        case .history: "No history yet"
        case .all: "No generations yet"
        }
    }

    static func category(for status: StudioJob.Status, needsPermission: Bool) -> Self {
        switch status {
        case .running: needsPermission ? .attention : .inProgress
        case .queued: .inProgress
        case .review, .failed, .interrupted: .attention
        case .accepted, .rejected: .history
        }
    }
}

/// Explicit filter changes choose a matching item. Background status changes
/// keep the current detail open, even after its row moves to another filter.
struct StudioGenerationSelection {
    var filter: StudioGenerationFilter = .attention
    var jobID: UUID?

    mutating func reconcile(allIDs: [UUID], matchingIDs: [UUID]) {
        if let jobID, allIDs.contains(jobID) { return }
        jobID = matchingIDs.first
    }

    mutating func changeFilter(to filter: StudioGenerationFilter, matchingIDs: [UUID]) {
        self.filter = filter
        jobID = matchingIDs.first
    }
}
