import SwiftUI
import AppKit

struct StudioReviewSheet: View {
    @Bindable var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var navigation = StudioGenerationSelection()
    @State private var revision = ""
    @State private var revisionCandidate: StudioCandidate?
    private var job: StudioJob? { store.manifest.jobs.first { $0.id == navigation.jobID } }

    private var matchingJobs: [StudioJob] { store.generationJobs(in: navigation.filter) }
    private var matchingIDs: [UUID] { matchingJobs.map(\.id) }
    private var listSelection: Binding<UUID?> {
        Binding(get: {
            navigation.jobID.flatMap { matchingIDs.contains($0) ? $0 : nil }
        }, set: { id in
            // List clears its selection when a row changes filter. The detail
            // remains selected until the user chooses another generation.
            if let id { navigation.jobID = id }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Generations").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Show:")
                        Picker("Show generations", selection: Binding(get: { navigation.filter }, set: { filter in
                            navigation.changeFilter(to: filter, matchingIDs: store.generationJobs(in: filter).map(\.id))
                        })) {
                            ForEach(StudioGenerationFilter.allCases) { filter in
                                Text("\(filter.title) (\(store.generationJobs(in: filter).count))").tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }.padding(12)
                    Divider()
                    List(selection: listSelection) {
                        ForEach(matchingJobs) { job in
                            HStack(spacing: 8) {
                                StudioGenerationRow(store: store, job: job)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let action = store.generationActionTitle(for: job) {
                                    Button(action) {
                                        navigation.jobID = job.id
                                        if [.failed, .interrupted].contains(job.status) { store.resume(job) }
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(store.isBusy && [.failed, .interrupted].contains(job.status))
                                    .accessibilityLabel("\(action) \(job.title), \(job.artwork?.role.title ?? "catalog")")
                                }
                            }.tag(job.id)
                        }
                    }
                    .overlay {
                        if matchingJobs.isEmpty {
                            Text(navigation.filter.emptyMessage)
                                .font(.callout).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).padding(20)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 350)
                ScrollView {
                    if let job {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(job.title).font(.title2.bold())
                            versionNavigation(for: job)
                            if [.running, .queued].contains(job.status) {
                                StudioArtworkProgressView(runtime: store.generations.runtimes[job.id], referenceURL: referenceURL(job), queued: job.status == .queued)
                                Button("Stop") { store.cancelGeneration(job.id) }
                                    .disabled(store.generations.runtimes[job.id]?.isStopping == true)
                            }
                            if let candidate = store.manifest.candidates.first(where: { $0.jobID == job.id }) {
                                artwork(candidate)
                            } else if let draft = job.draft {
                                Text(draft.notes).textSelection(.enabled)
                                ForEach(draft.records, id: \.localID) { record in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(record.title).font(.headline)
                                        Text(record.type.capitalized + (record.year.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                                        Text(record.summary).font(.callout).textSelection(.enabled)
                                        ForEach(record.sources, id: \.self) { source in
                                            if let url = URL(string: source) { Link(url.host ?? source, destination: url).font(.caption) }
                                        }
                                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 10))
                                }
                                if job.status == .review {
                                    HStack {
                                        Button("Reject Draft") { store.decideDraft(job, accept: false) }
                                        Spacer()
                                        Button("Accept & Save \(draft.records.count) Records") { store.decideDraft(job, accept: true) }.buttonStyle(.borderedProminent)
                                    }.disabled(store.isBusy)
                                }
                            }
                            if let message = job.message { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
                            if [.failed, .interrupted].contains(job.status) {
                                HStack {
                                    Button("Retry") { store.resume(job) }
                                    Button("Discard") { store.discardUnfinishedJob(job.id) }
                                }.disabled(store.isBusy)
                            }
                            DisclosureGroup("Request and conversation") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(job.prompt).font(.caption).textSelection(.enabled)
                                    if let threadID = job.threadID { Text("Codex conversation: \(threadID)").font(.caption.monospaced()).textSelection(.enabled) }
                                    if let history = store.historyURL, let url = try? StudioFiles.resolved(job.directory, in: history) {
                                        Button("Show Job Files") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    }
                                }.padding(.top, 8)
                            }

                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ContentUnavailableView("Choose a generation", systemImage: "clock.arrow.circlepath")
                    }
                }.frame(minWidth: 590)
                    .id(navigation.jobID)
            }
        }.frame(width: 1020, height: 740)
            .sheet(item: $revisionCandidate) { candidate in
                if let item = store.items.first(where: { item in
                    if let userID = candidate.userID { return item.id == "user:\(userID)" }
                    if let recordID = candidate.recordID { return item.recordID == recordID }
                    return item.assetPath == candidate.assetPath
                }) {
                    StudioGenerateSheet(store: store, item: item, revising: candidate, initialInstructions: revision, returnTitle: "Back to Generations")
                }
            }
            .onChange(of: matchingIDs, initial: true) {
                navigation.reconcile(allIDs: store.manifest.jobs.map(\.id), matchingIDs: matchingIDs)
            }
            .onChange(of: navigation.jobID) { revision = "" }
            .alert("Studio couldn’t finish that action", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }

    private func referenceURL(_ job: StudioJob) -> URL? {
        guard let history = store.historyURL, let path = job.artwork?.references.first else { return nil }
        return try? StudioFiles.resolved(job.directory + "/" + path, in: history)
    }

    private func selectVersion(_ job: StudioJob) {
        navigation.filter = store.generationFilter(for: job)
        navigation.jobID = job.id
    }

    @ViewBuilder private func versionNavigation(for job: StudioJob) -> some View {
        let source = store.sourceGeneration(for: job)
        let revisions = store.revisions(of: job)
        if source != nil || !revisions.isEmpty {
            HStack {
                if let source {
                    Button("Previous Version") { selectVersion(source) }
                }
                if revisions.count == 1, let revision = revisions.first {
                    Button("View Revision") { selectVersion(revision) }
                } else if !revisions.isEmpty {
                    Menu("Revisions") {
                        ForEach(revisions) { revision in
                            Button(revision.createdAt.formatted(date: .abbreviated, time: .standard)) {
                                selectVersion(revision)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func artwork(_ candidate: StudioCandidate) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack {
                Text("Current").font(.caption).foregroundStyle(.secondary)
                StudioImagePreview(url: store.artworkURL(for: candidate.assetPath), revision: store.artworkRevision)
            }
            VStack {
                Text(candidate.decision == .pending ? "Candidate" : candidate.decision.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                StudioImagePreview(url: store.historyURL.flatMap { try? StudioFiles.resolved(candidate.file, in: $0) })
            }
        }.frame(height: 370)
        Text("\(candidate.role.title) · \(Int(candidate.role.exportSize.width)) × \(Int(candidate.role.exportSize.height)) export").font(.caption).foregroundStyle(.secondary)
        if candidate.decision == .pending {
            HStack {
                Button("Reject") { store.decide(candidate, accept: false) }
                Spacer()
                StudioAcceptArtworkButton(store: store, candidate: candidate)
            }.disabled(store.isBusy)
        }
        Divider()
        TextField("Describe a revision", text: $revision, axis: .vertical).lineLimit(3...6)
        Button("Create Revised Candidate") {
            revisionCandidate = candidate
        }.disabled(store.isBusy || revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
