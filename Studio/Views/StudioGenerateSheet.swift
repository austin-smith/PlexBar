import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StudioGenerateSheet: View {
    @Bindable var store: StudioStore
    let item: StudioGalleryItem
    var revising: StudioCandidate? = nil
    var initialInstructions = ""
    var returnTitle = "Back to Collection"
    @Environment(\.dismiss) private var dismiss
    @State private var role = StudioArtworkRole.poster
    @State private var instructions = ""
    @State private var referenceFileURL: URL?
    @State private var referenceSource = ReferenceSource.file
    @State private var imageAddress = ""
    @State private var requestedAddress: String?
    @State private var downloadedReferenceURL: URL?
    @State private var referenceError: String?
    @State private var savedInstructions: StudioArtworkInstructions?
    @State private var errorMessage: String?
    @State private var showingPrompt = false
    @State private var jobID: UUID?
    @State private var revisionCandidate: StudioCandidate?
    @State private var returnToJobID: UUID?
    @State private var didLoad = false

    private var activeRevision: StudioCandidate? { revisionCandidate ?? revising }
    private var job: StudioJob? { store.manifest.jobs.first { $0.id == jobID } }
    private var isGenerating: Bool { job?.status == .running || job?.status == .queued }
    private var candidate: StudioCandidate? {
        guard job?.status == .review else { return nil }
        return store.manifest.candidates.first { $0.jobID == jobID && $0.decision == .pending }
    }
    private var failed: Bool { job?.status == .failed || job?.status == .interrupted }
    private var title: String {
        if isGenerating { return "Generating artwork" }
        if candidate != nil { return "Review artwork" }
        return activeRevision == nil ? "Create artwork" : "Revise artwork"
    }
    private var jobReferenceURL: URL? {
        guard let job, let path = job.artwork?.references.first, let history = store.historyURL else { return referenceURL }
        return try? StudioFiles.resolved(job.directory + "/" + path, in: history)
    }

    private enum ReferenceSource: String, CaseIterable {
        case file = "File", url = "URL"
    }

    private var prompt: String? {
        try? savedInstructions?.prompt(item: item, role: role,
                                      artDirection: instructions, revising: activeRevision != nil)
    }

    private var roles: [StudioArtworkRole] {
        switch item.category { case .users: [.avatar]; case .audiobooks: [.cover]; default: [.poster, .backdrop] }
    }

    private var referencePath: String {
        if let record = store.pack?.records.first(where: { $0.id == item.recordID }) {
            return record.metadata[role == .backdrop ? "art" : "thumb"]?.string ?? ""
        }
        return item.assetPath ?? ""
    }

    private var referenceURL: URL? {
        if let revising = activeRevision, let history = store.historyURL,
           let prior = store.manifest.jobs.first(where: { $0.id == revising.jobID }),
           let reference = prior.artwork?.references.first {
            return try? StudioFiles.resolved(prior.directory + "/" + reference, in: history)
        }
        return referenceSource == .url ? downloadedReferenceURL : referenceFileURL ?? store.artworkURL(for: referencePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title2.bold())
            Text(item.title).font(.title3).foregroundStyle(.secondary)
            Group {
                if isGenerating {
                    StudioArtworkProgressView(runtime: jobID.flatMap { store.generations.runtimes[$0] }, referenceURL: jobReferenceURL, queued: job?.status == .queued)
                } else if let candidate {
                    VStack(spacing: 12) {
                        StudioImageView(url: store.historyURL.flatMap { try? StudioFiles.resolved(candidate.file, in: $0) })
                            .accessibilityLabel("Generated artwork")
                        Text("\(candidate.role.title) · \(Int(candidate.role.exportSize.width)) × \(Int(candidate.role.exportSize.height))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if failed, let message = job?.message {
                            Label(job?.status == .interrupted ? "Generation stopped" : "Generation failed",
                                  systemImage: job?.status == .interrupted ? "stop.circle" : "exclamationmark.triangle")
                                .font(.headline)
                            if job?.status == .failed {
                                Text(message).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        generationForm
                    }
                }
            }.frame(height: 460)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("View Prompt…") { showingPrompt = true }.disabled(prompt == nil)
                Spacer()
                if isGenerating {
                    Button("Stop") { if let jobID { store.cancelGeneration(jobID) } }
                        .disabled(jobID.flatMap { store.generations.runtimes[$0] }?.isStopping == true)
                    Button(returnTitle) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                } else if let candidate {
                    Button("Discard") { decide(candidate, accept: false) }
                    Button("Revise") { beginRevision(candidate) }
                    StudioAcceptArtworkButton(store: store, candidate: candidate, onAccepted: { dismiss() }, onFailure: {
                        errorMessage = store.errorMessage
                        store.errorMessage = nil
                    })
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(returnToJobID == nil ? "Cancel" : "Back to Review", action: cancelEditing)
                        .keyboardShortcut(.cancelAction)
                    Button(failed ? "Try Again" : "Generate", action: generate)
                        .buttonStyle(.borderedProminent)
                        .disabled(prompt == nil || referenceURL == nil || store.isBusy)
                        .disabled(activeRevision != nil && instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 620)
            .interactiveDismissDisabled(isGenerating)
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                role = revising?.role ?? roles[0]
                instructions = initialInstructions
                do {
                    let loaded = try store.loadArtworkInstructions()
                    try loaded.validate()
                    savedInstructions = loaded
                } catch { errorMessage = error.localizedDescription }
            }
            .sheet(isPresented: $showingPrompt) {
                if let previewPrompt = isGenerating || candidate != nil ? job?.prompt : prompt {
                    StudioPromptPreview(prompt: previewPrompt)
                }
            }
            .onChange(of: imageAddress) { clearDownloadedReference() }
            .onChange(of: referenceSource) { clearDownloadedReference() }
            .task(id: requestedAddress) {
                guard let address = requestedAddress else { return }
                do {
                    let file = try await StudioReferenceDownload.load(address)
                    guard !Task.isCancelled else {
                        try? FileManager.default.removeItem(at: file)
                        return
                    }
                    downloadedReferenceURL = file
                    requestedAddress = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    referenceError = error.localizedDescription
                    requestedAddress = nil
                }
            }
            .onDisappear { clearDownloadedReference() }
    }

    private var generationForm: some View {
        Form {
            Picker("Artwork", selection: $role) { ForEach(roles) { Text($0.title).tag($0) } }
                .disabled(activeRevision != nil)
            LabeledContent("Dimensions") {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Generate: \(role.generationSize)")
                    Text("Save: \(Int(role.exportSize.width)) × \(Int(role.exportSize.height))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if activeRevision == nil {
                Picker("Reference", selection: $referenceSource) {
                    ForEach(ReferenceSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Reference image") {
                    if referenceSource == .file {
                        HStack {
                            Text(referenceURL?.lastPathComponent ?? "Choose an image")
                                .lineLimit(1).truncationMode(.middle)
                                .help(referenceURL?.path ?? "")
                            Button("Choose…", action: chooseReference)
                        }
                    } else {
                        HStack {
                            TextField("https://…", text: $imageAddress)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 220)
                                .accessibilityLabel("Image URL")
                                .onSubmit(loadReference)
                            if requestedAddress != nil {
                                ProgressView().controlSize(.small)
                            }
                            Button("Load", action: loadReference)
                                .disabled(imageAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || requestedAddress != nil)
                        }
                    }
                }
                if let referenceError {
                    Text(referenceError).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            if let referenceURL {
                HStack {
                    VStack {
                        Text("Image 1 · Reference").font(.caption)
                        StudioImageView(url: referenceURL)
                    }
                    if let revising = activeRevision, let history = store.historyURL {
                        VStack {
                            Text("Image 2 · Previous candidate").font(.caption)
                            StudioImageView(url: try? StudioFiles.resolved(revising.file, in: history))
                        }
                    }
                }.frame(height: 180)
            }
            TextField("Additional instructions", text: $instructions, axis: .vertical).lineLimit(4...8)
        }.formStyle(.grouped)
    }

    private func beginRevision(_ candidate: StudioCandidate) {
        do {
            savedInstructions = try store.loadArtworkInstructions()
            returnToJobID = jobID
            revisionCandidate = candidate
            role = candidate.role
            instructions = ""
            errorMessage = nil
            jobID = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func cancelEditing() {
        if let returnToJobID {
            jobID = returnToJobID
            self.returnToJobID = nil
            errorMessage = nil
        } else { dismiss() }
    }

    private func decide(_ candidate: StudioCandidate, accept: Bool) {
        errorMessage = nil
        if store.decide(candidate, accept: accept) { dismiss() }
        else {
            errorMessage = store.errorMessage ?? "The artwork could not be saved."
            store.errorMessage = nil
        }
    }

    private func generate() {
        guard let prompt else { return }
        errorMessage = nil
        if let id = store.generate(item: item, role: role, instructions: instructions, referencePath: referencePath,
                                   revising: activeRevision, referenceFileURL: referenceURL, expectedPrompt: prompt) {
            jobID = id
            returnToJobID = nil
        } else {
            errorMessage = store.errorMessage
            store.errorMessage = nil
        }
    }

    private func chooseReference() {
        let panel = NSOpenPanel()
        panel.title = "Choose Reference Image"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { referenceFileURL = url }
    }

    private func loadReference() {
        guard requestedAddress == nil, !imageAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        clearDownloadedReference()
        requestedAddress = imageAddress
    }

    private func clearDownloadedReference() {
        requestedAddress = nil
        referenceError = nil
        if let downloadedReferenceURL {
            try? FileManager.default.removeItem(at: downloadedReferenceURL)
            self.downloadedReferenceURL = nil
        }
    }
}
