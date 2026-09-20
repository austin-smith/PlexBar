import AppKit
import PlexMockData
import Observation

@Observable @MainActor
final class StudioStore {
    var pack: StudioPack?
    var manifest = StudioManifest()
    var packURL: URL?
    private(set) var historyURL: URL?
    private var contentFingerprint: [String: String] = [:]
    private let contentURLOverride: URL?
    private let instructionsURLOverride: URL?
    private let codexExecutableOverride: String?

    init(contentURL: URL? = nil, instructionsURL: URL? = nil, codexExecutable: String? = nil) {
        contentURLOverride = contentURL
        instructionsURLOverride = instructionsURL
        codexExecutableOverride = codexExecutable
    }
    var items: [StudioGalleryItem] = []
    var selection: String?
    var category = StudioCategory.all
    var search = ""
    var errorMessage: String?
    var statusMessage = ""
    var isBusy = false
    var activity = ""
    let generations = StudioGenerationCoordinator()
    var codexExecutable: String { codexExecutableOverride ?? UserDefaults.standard.string(forKey: "studio.codexExecutable") ?? StudioCodexConnection.defaultExecutable }
    var validationIssues: [StudioValidationIssue] = []
    var didValidate = false
    var artworkRevision = 0
    var hasActiveGenerations: Bool { manifest.jobs.contains { $0.status == .running || $0.status == .queued } }

    var selectedItem: StudioGalleryItem? { items.first { $0.id == selection } }
    var selectedRecord: StudioCatalogRecord? { pack?.records.first { $0.id == selectedItem?.recordID } }
    var visibleItems: [StudioGalleryItem] {
        items.filter { (category == .all || $0.category == category) && (search.isEmpty || $0.title.localizedStandardContains(search) || $0.subtitle.localizedStandardContains(search)) }
    }
    var pendingCandidates: [StudioCandidate] { manifest.candidates.filter { $0.decision == .pending } }
    var windowTitle: String { "PlexBar Studio" }

    func loadContent() async {
        guard !isBusy, !hasActiveGenerations else { return }
        isBusy = true
        activity = "Loading PlexBar’s mock content…"
        defer { isBusy = false }
        do {
            let url = try contentURLOverride ?? StudioFiles.repositoryContentURL
            let history = try StudioFiles.historyURL(in: url)
            try StudioContentTransaction.recover(at: url)
            let loaded = try await Task.detached {
                let before = try StudioFiles.fingerprints(at: url)
                let pack = try StudioFiles.loadPack(at: url)
                guard try StudioFiles.fingerprints(at: url) == before else {
                    throw StudioError.invalid("The mock content changed while loading. Try Reload Content again.")
                }
                return (pack, before)
            }.value
            var loadedManifest = FileManager.default.fileExists(atPath: history.appending(path: "studio.json").path)
                ? try StudioFiles.loadManifest(at: history) : StudioManifest()
            for index in loadedManifest.jobs.indices where [.running, .queued].contains(loadedManifest.jobs[index].status) {
                loadedManifest.jobs[index].status = .interrupted
                loadedManifest.jobs[index].message = "Studio closed before this generation completed. Retry to continue."
            }
            if !loadedManifest.jobs.isEmpty { try StudioFiles.saveManifest(loadedManifest, at: history) }
            pack = loaded.0
            contentFingerprint = loaded.1
            packURL = url
            historyURL = history
            manifest = loadedManifest
            didValidate = false
            selection = nil
            refreshItems()
            statusMessage = ""
        } catch { errorMessage = "Couldn’t load PlexBar’s mock content. \(error.localizedDescription)" }
    }

    private func saveContent(_ updatedPack: StudioPack, manifest updatedManifest: StudioManifest, files: [String: Data] = [:]) throws {
        guard let packURL else { throw StudioError.invalid("PlexBar’s mock content is not loaded.") }
        contentFingerprint = try StudioFiles.commitContent(updatedPack, manifest: updatedManifest, at: packURL,
                                                           expected: contentFingerprint, files: files)
        pack = updatedPack
        manifest = updatedManifest
        didValidate = false
        artworkRevision += 1
        refreshItems()
        statusMessage = "Saved to PlexBar’s mock content"
    }

    func validate() async {
        guard let pack, let packURL, !isBusy else { return }
        isBusy = true
        activity = "Validating catalog and artwork…"
        defer { isBusy = false }
        validationIssues = await Task.detached { pack.validate() + StudioFiles.validateAssets(pack, at: packURL) }.value
        didValidate = true
        statusMessage = validationIssues.isEmpty ? "Validation passed · \(pack.records.count) records and \(pack.assets.count) images" : "\(validationIssues.count) validation issues"
    }

    func applyMetadataJSON(_ text: String, recordID: String) throws {
        guard !isBusy else { throw StudioError.invalid("Wait for the current operation to finish before saving edits.") }
        guard var pack, let index = pack.records.firstIndex(where: { $0.id == recordID }) else { throw StudioError.invalid("The selected record no longer exists.") }
        let metadata = try JSONDecoder().decode(StudioJSON.self, from: Data(text.utf8))
        guard metadata["ratingKey"]?.string == recordID else { throw StudioError.invalid("An existing rating key cannot be changed.") }
        pack.records[index].metadata = metadata
        for descendantIndex in pack.records.indices {
            if pack.records[descendantIndex].parentID == recordID {
                pack.records[descendantIndex].metadata["parentTitle"] = metadata["title"]
            }
            if pack.records[descendantIndex].metadata["grandparentRatingKey"]?.string == recordID {
                pack.records[descendantIndex].metadata["grandparentTitle"] = metadata["title"]
            }
        }
        try requireValid(pack)
        try saveContent(pack, manifest: manifest)
    }

    func userProfile(id: Int) throws -> PlexMockServerPayload.User {
        guard let value = pack?.payload["users"]?.array?.first(where: { $0["id"]?.integer == id }) else {
            throw StudioError.invalid("The selected user no longer exists.")
        }
        return try JSONDecoder().decode(PlexMockServerPayload.User.self, from: value.encoded())
    }

    func saveUser(_ user: PlexMockServerPayload.User, replacing original: PlexMockServerPayload.User,
                  signedIn: Bool, originalAuthenticatedUserID: Int) throws {
        guard !isBusy else { throw StudioError.invalid("Wait for the current operation to finish before saving edits.") }
        guard user.id == original.id, try userProfile(id: original.id) == original,
              var pack, var users = pack.payload["users"]?.array,
              let index = users.firstIndex(where: { $0["id"]?.integer == original.id }),
              pack.payload["authenticatedUserID"]?.integer == originalAuthenticatedUserID else {
            throw StudioError.invalid("This profile changed while editing. Reopen the user to load the latest details.")
        }
        let encoded = try JSONDecoder().decode(StudioJSON.self, from: JSONEncoder().encode(user))
        for field in ["username", "email", "friendlyName", "avatar", "devices"] {
            users[index][field] = encoded[field]
        }
        pack.payload["users"] = .array(users)
        if signedIn { pack.payload["authenticatedUserID"] = .integer(user.id) }
        try requireValid(pack)
        try saveContent(pack, manifest: manifest)
    }

    func nextDeviceID(among draftDevices: [PlexMockServerPayload.Device]) throws -> Int {
        let existing = (pack?.payload["users"]?.array ?? []).flatMap { $0["devices"]?.array ?? [] }
            .compactMap { $0["id"]?.integer }
        let maximum = (existing + draftDevices.map(\.id)).max() ?? 0
        guard maximum < Int.max else { throw StudioError.invalid("There are no available device IDs.") }
        return maximum + 1
    }

    @discardableResult
    func generate(item: StudioGalleryItem, role: StudioArtworkRole, instructions: String, referencePath: String, revising: StudioCandidate? = nil,
                  referenceFileURL: URL? = nil, expectedPrompt: String? = nil) -> UUID? {
        guard !isBusy, let historyURL, let packURL, let pack else {
            errorMessage = isBusy ? "Wait for the current operation to finish." : "PlexBar’s mock content is not loaded."
            return nil
        }
        do {
            if let revising {
                guard manifest.candidates.contains(where: { $0.id == revising.id && $0.jobID == revising.jobID }),
                      manifest.jobs.contains(where: { $0.id == revising.jobID }) else {
                    throw StudioError.invalid("The source generation is no longer available.")
                }
            }
            let referenceURL: URL
            if let revising, let prior = manifest.jobs.first(where: { $0.id == revising.jobID }),
               let reference = prior.artwork?.references.first {
                referenceURL = try StudioFiles.resolved(prior.directory + "/" + reference, in: historyURL)
            } else if let referenceFileURL {
                referenceURL = referenceFileURL
            } else if let reference = pack.assets.first(where: { $0.path == referencePath }) {
                referenceURL = try StudioFiles.resolved(reference.resource, in: packURL)
            } else { throw StudioError.invalid("Choose a reference image.") }
            let prompt = try loadArtworkInstructions().prompt(item: item, role: role,
                                                             artDirection: instructions, revising: revising != nil)
            if let expectedPrompt, expectedPrompt != prompt {
                throw StudioError.invalid("Artwork instructions changed since this window opened. Reopen Create Artwork to review the current prompt.")
            }
            let record = item.recordID.flatMap { id in pack.records.first { $0.id == id } }
            let user: PlexMockServerPayload.User?
            if item.category == .users {
                guard let id = Int(item.id.dropFirst("user:".count)), role == .avatar else {
                    throw StudioError.invalid("Choose a user and the avatar artwork type.")
                }
                user = try userProfile(id: id)
            } else { user = nil }
            let path: String
            if let user {
                path = try StudioAvatarArtwork.path(for: user, in: pack)
            } else if let record, record.type == "movie" {
                path = try StudioMovieArtwork.path(for: record, role: role, in: pack)
            } else {
                let existing = record.flatMap { pack.artwork(for: $0).first { $0.role == role } }
                path = revising?.assetPath ?? existing?.path ?? item.assetPath ?? "/mock/art/studio/\(item.recordID ?? UUID().uuidString)/\(role.rawValue).\(role == .backdrop ? "jpg" : "png")"
            }
            var job = StudioJob(id: UUID(), title: item.title, kind: .artwork, prompt: prompt, createdAt: Date())
            // Revisions carry the original reference and previous candidate explicitly.
            // A new conversation avoids sharing mutable thread history between parallel revisions.
            job.executable = codexExecutable
            let directory = try StudioFiles.resolved(job.directory, in: historyURL)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var urls = [referenceURL]
            if let revising { urls.append(try StudioFiles.resolved(revising.file, in: historyURL)) }
            var paths: [String] = [], hashes: [String] = []
            for (index, url) in urls.enumerated() {
                let data = try StudioFiles.normalizedReference(at: url)
                let path = "reference-\(index + 1).png"
                try data.write(to: directory.appending(path: path), options: .atomic)
                paths.append(path); hashes.append(StudioFiles.hash(data))
            }
            job.artwork = .init(sourceCandidateID: revising?.id, recordID: item.recordID, userID: user?.id, userAvatarPath: user?.avatar, assetPath: path, role: role, references: paths, referenceHashes: hashes,
                                destination: try destinationSnapshot(path: path))
            try enqueue(job)
            return job.id
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func research(title: String, kind: String, notes: String) {
        guard !isBusy, pack != nil else { return }
        do { try enqueue(StudioJob(id: UUID(), title: title, kind: .catalog,
                                  prompt: StudioTitleDraft.researchPrompt(title: title, kind: kind, notes: notes), createdAt: Date())) }
        catch { errorMessage = error.localizedDescription }
    }

    private func enqueue(_ job: StudioJob) throws {
        guard !generations.isShuttingDown else { throw StudioError.invalid("Studio is quitting.") }
        guard let historyURL else { throw StudioError.invalid("PlexBar’s mock content is not loaded.") }
        try FileManager.default.createDirectory(at: StudioFiles.resolved(job.directory, in: historyURL), withIntermediateDirectories: true)
        var updated = manifest
        var queued = job
        queued.executable = queued.executable ?? codexExecutable
        updated.jobs.append(queued)
        try StudioFiles.saveManifest(updated, at: historyURL)
        manifest = updated
        scheduleGenerations()
    }

    func resume(_ job: StudioJob) {
        guard !isBusy, !generations.isShuttingDown, pack != nil,
              let index = manifest.jobs.firstIndex(where: { $0.id == job.id }),
              [.failed, .interrupted].contains(manifest.jobs[index].status) else { return }
        do {
            var updated = manifest
            updated.jobs[index].status = .queued
            updated.jobs[index].message = nil
            try StudioFiles.saveManifest(updated, at: requireHistoryURL())
            manifest = updated
            scheduleGenerations()
        } catch { errorMessage = error.localizedDescription }
    }

    private func scheduleGenerations() {
        while generations.hasCapacity, let job = manifest.jobs.first(where: { $0.status == .queued }) {
            execute(jobID: job.id)
        }
    }

    private func execute(jobID: UUID) {
        guard let historyURL, let index = manifest.jobs.firstIndex(where: { $0.id == jobID }) else { return }
        manifest.jobs[index].status = .running
        manifest.jobs[index].message = nil
        let job = manifest.jobs[index]
        generations.start(id: jobID, operation: { [self] codex in
            do {
                try StudioFiles.saveManifest(manifest, at: historyURL)
                let directory = try StudioFiles.resolved(job.directory, in: historyURL)
                let references = try (job.artwork?.references ?? []).map { try StudioFiles.resolved($0, in: directory) }
                let result = try await codex.run(executable: job.executable ?? codexExecutable, directory: directory, prompt: job.prompt,
                                                references: references, threadID: job.threadID,
                                                schema: job.kind == .catalog ? StudioTitleDraft.outputSchema : nil,
                                                requiresImages: job.kind == .artwork) { threadID, model in
                    guard let currentIndex = self.manifest.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                    self.manifest.jobs[currentIndex].threadID = threadID
                    self.manifest.jobs[currentIndex].model = model
                    try StudioFiles.saveManifest(self.manifest, at: historyURL)
                }
                try Task.checkCancellation()
                guard let pack else { throw StudioError.invalid("PlexBar’s mock content is no longer loaded.") }
                guard let index = manifest.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                var updated = manifest
                var files: [String: Data] = [:]
                files[job.directory + "/transcript.txt"] = Data(codex.transcript.utf8)
                if let artwork = job.artwork {
                    guard let image = result.images.last, image["status"]?.string == "completed" else {
                        throw StudioError.invalid("Codex completed without a successful image-generation result. Review its transcript before resuming.")
                    }
                    let data: Data
                    if let path = image["savedPath"]?.string {
                        data = try Data(contentsOf: URL(fileURLWithPath: path))
                    } else if let encoded = image["result"]?.string, let decoded = Data(base64Encoded: encoded), !decoded.isEmpty {
                        data = decoded
                    } else { throw StudioError.invalid("Codex returned no readable image file or image data.") }
                    // A bad aspect ratio remains reviewable; acceptance checks the required dimensions.
                    let file = "candidates/\(job.id.uuidString).png"
                    files[file] = data
                    updated.candidates.append(.init(id: job.id, title: job.title, recordID: artwork.recordID, userID: artwork.userID,
                        assetPath: artwork.assetPath, role: artwork.role, file: file, prompt: job.prompt, revisedPrompt: image["revisedPrompt"]?.string,
                        model: result.model, jobID: job.id, referenceHashes: artwork.referenceHashes,
                        outputHash: StudioFiles.hash(data), createdAt: Date(), decision: .pending))
                } else {
                    let draft = try JSONDecoder().decode(StudioTitleDraft.self, from: Data(result.text.utf8))
                    _ = try draft.compile(into: pack)
                    updated.jobs[index].draft = draft
                }
                updated.jobs[index].status = .review
                try StudioFiles.saveHistory(updated, at: historyURL, files: files)
                manifest = updated
                statusMessage = "\(job.title) is ready to review"
            } catch {
                guard let index = manifest.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                manifest.jobs[index].status = error is CancellationError ? .interrupted : .failed
                manifest.jobs[index].message = error is CancellationError ? "Generation stopped." : error.localizedDescription
                do {
                    try StudioFiles.saveManifest(manifest, at: historyURL)
                    try Data(codex.transcript.utf8).write(to: StudioFiles.resolved(job.directory + "/transcript.txt", in: historyURL), options: .atomic)
                } catch {
                    manifest.jobs[index].message = (manifest.jobs[index].message ?? "") + "\nCould not save job history: \(error.localizedDescription)"
                }
                if error is CancellationError { statusMessage = "Generation stopped." }
                else {
                    statusMessage = "\(job.title) could not be generated"
                    // The affected job owns its failure; another job may be under review.
                }
            }

        }, didFinish: { [weak self] in self?.scheduleGenerations() })
    }

    func cancelGeneration(_ id: UUID) {
        if generations.runtimes[id] != nil {
            generations.stop(id: id)
        } else if let index = manifest.jobs.firstIndex(where: { $0.id == id && $0.status == .queued }) {
            do {
                var updated = manifest
                updated.jobs[index].status = .interrupted
                updated.jobs[index].message = "Generation stopped."
                try StudioFiles.saveManifest(updated, at: requireHistoryURL())
                manifest = updated
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func shutdownGenerations() async {
        await generations.shutdown()
        for job in manifest.jobs where job.status == .queued { cancelGeneration(job.id) }
    }

    func discardUnfinishedJob(_ id: UUID) {
        guard let index = manifest.jobs.firstIndex(where: { $0.id == id }),
              [.failed, .interrupted].contains(manifest.jobs[index].status) else { return }
        do {
            var updated = manifest
            updated.jobs[index].status = .rejected
            try StudioFiles.saveManifest(updated, at: requireHistoryURL())
            manifest = updated
        } catch { errorMessage = error.localizedDescription }
    }

    private func requireHistoryURL() throws -> URL {
        guard let historyURL else { throw StudioError.invalid("Generation history is unavailable.") }
        return historyURL
    }

    func destinationSnapshot(path: String) throws -> StudioJob.Destination {
        let hash = try artworkURL(for: path).map { StudioFiles.hash(try Data(contentsOf: $0)) }
        let accepted = manifest.candidates.filter { $0.assetPath == path && $0.decision == .accepted }
            .max { ($0.decidedAt ?? $0.createdAt) < ($1.decidedAt ?? $1.createdAt) }
        return .init(path: path, hash: hash, acceptedCandidateID: accepted?.id)
    }

    func needsReplacementConfirmation(_ candidate: StudioCandidate) -> Bool {
        guard let original = manifest.jobs.first(where: { $0.id == candidate.jobID })?.artwork?.destination else { return false }
        return (try? destinationSnapshot(path: candidate.assetPath)) != original
    }

    func decideDraft(_ job: StudioJob, accept: Bool) {
        guard !isBusy, let historyURL, let pack, let index = manifest.jobs.firstIndex(where: { $0.id == job.id }),
              manifest.jobs[index].status == .review, let draft = job.draft else { return }
        do {
            let result = accept ? try draft.compile(into: pack) : (pack, "")
            var updated = manifest
            updated.jobs[index].status = accept ? .accepted : .rejected
            if accept { try saveContent(result.0, manifest: updated) }
            else { try StudioFiles.saveHistory(updated, at: historyURL); manifest = updated }
            statusMessage = accept ? "Title saved to PlexBar’s mock content" : "Draft rejected"
            if accept { category = .all; search = ""; selection = "media:\(result.1)" }
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func decide(_ candidate: StudioCandidate, accept: Bool, replacing expectedDestination: StudioJob.Destination? = nil) -> Bool {
        guard !isBusy, let historyURL, var pack,
              let index = manifest.candidates.firstIndex(where: { $0.id == candidate.id }),
              manifest.candidates[index].decision == .pending else { return false }
        do {
            var files: [String: Data] = [:]
            if accept {
                if needsReplacementConfirmation(candidate) {
                    guard let expectedDestination, try destinationSnapshot(path: candidate.assetPath) == expectedDestination else {
                        throw StudioError.invalid("The accepted artwork changed after this generation started. Review the current artwork before replacing it.")
                    }
                }
                if let record = pack.records.first(where: { $0.id == candidate.recordID }), record.type == "movie" {
                    let expectedPath = try StudioMovieArtwork.path(for: record, role: candidate.role, in: pack)
                    guard candidate.assetPath == expectedPath else {
                        throw StudioError.invalid("The poster or backdrop destination does not match the movie’s artwork folder.")
                    }
                }
                if let userID = candidate.userID {
                    guard candidate.role == .avatar,
                          let artwork = manifest.jobs.first(where: { $0.id == candidate.jobID })?.artwork,
                          artwork.userID == userID,
                          var users = pack.payload["users"]?.array,
                          let userIndex = users.firstIndex(where: { $0["id"]?.integer == userID }),
                          (users[userIndex]["avatar"]?.string == artwork.userAvatarPath ||
                           users[userIndex]["avatar"]?.string == candidate.assetPath) else {
                        throw StudioError.invalid("This user’s avatar selection changed after generation started. Create new artwork for the current profile.")
                    }
                    let profile = try JSONDecoder().decode(PlexMockServerPayload.User.self, from: users[userIndex].encoded())
                    guard candidate.assetPath == artwork.assetPath,
                          candidate.assetPath == (try StudioAvatarArtwork.path(for: profile, in: pack)) else {
                        throw StudioError.invalid("The avatar destination no longer matches this user. Create new artwork for the current profile.")
                    }
                    users[userIndex]["avatar"] = .string(candidate.assetPath)
                    pack.payload["users"] = .array(users)
                }
                let data = try Data(contentsOf: StudioFiles.resolved(candidate.file, in: historyURL))
                guard StudioFiles.hash(data) == candidate.outputHash else { throw StudioError.invalid("The candidate file changed since generation.") }
                let output = try StudioFiles.exportImage(data, role: candidate.role)
                let resource = pack.assets.first { $0.path == candidate.assetPath }?.resource ?? String(candidate.assetPath.dropFirst("/mock/".count))
                files[resource] = output
                if let recordID = candidate.recordID, let recordIndex = pack.records.firstIndex(where: { $0.id == recordID }) {
                    pack.records[recordIndex].metadata[candidate.role == .backdrop ? "art" : "thumb"] = .string(candidate.assetPath)
                    for childIndex in pack.records.indices {
                        if pack.records[childIndex].parentID == recordID {
                            pack.records[childIndex].metadata[candidate.role == .backdrop ? "art" : "parentThumb"] = .string(candidate.assetPath)
                        }
                        if pack.records[childIndex].metadata["grandparentRatingKey"]?.string == recordID {
                            pack.records[childIndex].metadata[candidate.role == .backdrop ? "art" : "grandparentThumb"] = .string(candidate.assetPath)
                        }
                    }
                }
                if !pack.assets.contains(where: { $0.path == candidate.assetPath }) {
                    pack.payload["artwork"] = .array((pack.payload["artwork"]?.array ?? []) + [.object(["path": .string(candidate.assetPath), "resource": .string(resource)])])
                }
                try requireValid(pack)
            }
            var updated = manifest
            updated.candidates[index].decidedAt = Date()
            updated.candidates[index].decision = accept ? .accepted : .rejected
            if let jobIndex = updated.jobs.firstIndex(where: { $0.id == candidate.jobID }) { updated.jobs[jobIndex].status = accept ? .accepted : .rejected }
            if accept { try saveContent(pack, manifest: updated, files: files) }
            else { try StudioFiles.saveHistory(updated, at: historyURL); manifest = updated }
            statusMessage = accept ? "Artwork saved to PlexBar’s mock content" : "Candidate rejected"
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func loadArtworkInstructions() throws -> StudioArtworkInstructions {
        let url = try instructionsURLOverride ?? StudioFiles.artworkInstructionsURL
        return try JSONDecoder().decode(StudioArtworkInstructions.self, from: Data(contentsOf: url))
    }

    func saveArtworkInstructions(_ instructions: StudioArtworkInstructions, replacing original: StudioArtworkInstructions) throws {
        try instructions.validate()
        let url = try instructionsURLOverride ?? StudioFiles.artworkInstructionsURL
        guard try loadArtworkInstructions() == original else {
            throw StudioError.invalid("Artwork instructions changed outside this window. Reopen Settings to load them before saving.")
        }
        try instructions.encoded().write(to: url, options: .atomic)
    }

    func artworkURL(for path: String?) -> URL? {
        guard let path, let packURL, let asset = pack?.assets.first(where: { $0.path == path }) else { return nil }
        return try? StudioFiles.resolved(asset.resource, in: packURL)
    }

    private func requireValid(_ pack: StudioPack) throws {
        let issues = pack.validate()
        guard issues.isEmpty else { throw StudioError.invalid(issues.map { "\($0.context): \($0.message)" }.joined(separator: "\n")) }
    }

    private func refreshItems() {
        guard let pack else { return }
        items = pack.records.filter(\.isTitle).map { record in
            StudioGalleryItem(id: "media:\(record.id)", title: record.title, subtitle: record.subtitle,
                              category: record.type == "movie" ? .movies : record.type == "show" ? .television : .audiobooks,
                              recordID: record.id, assetPath: nil, previewURL: artworkURL(for: record.metadata["thumb"]?.string), ratio: record.type == "album" ? 1 : 2.0 / 3,
                              sortTitle: record.sortTitle)
        }
        items += (pack.payload["users"]?.array ?? []).compactMap { value in
            do {
                let user = try JSONDecoder().decode(PlexMockServerPayload.User.self, from: value.encoded())
                let deviceCount = user.devices.count
                let subtitle = "\(deviceCount) " + (deviceCount == 1 ? "device" : "devices")
                return StudioGalleryItem(id: "user:\(user.id)", title: user.name, subtitle: subtitle, category: .users,
                                         recordID: nil, assetPath: user.avatar, previewURL: artworkURL(for: user.avatar), ratio: 1)
            } catch { errorMessage = error.localizedDescription; return nil }
        }
        items.sort(by: StudioGalleryItem.orderedByTitle)
    }

}
