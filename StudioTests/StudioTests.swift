import Foundation
import ImageIO
import Testing
@testable import PlexBarStudio

@Suite struct StudioTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "studio-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func currentPackPassesBothEditorAndRuntimeValidation() throws {
        let pack = try StudioFiles.loadPack(at: StudioFiles.repositoryContentURL)
        #expect(pack.validate().isEmpty)
        #expect(try StudioFiles.validateAssets(pack, at: StudioFiles.repositoryContentURL).isEmpty)
    }

    @Test func resourcePathsCannotEscapeThroughTraversalOrSymlinks() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) { try StudioFiles.resolved("../outside.png", in: root) }
        #expect(throws: (any Error).self) { try StudioFiles.resolved("/outside.png", in: root) }
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: root.deletingLastPathComponent())
        #expect(throws: (any Error).self) { try StudioFiles.resolved("link/outside.png", in: root) }
    }

    private func copyContent(to root: URL) throws -> URL {
        let target = root.appending(path: "MockServer")
        try FileManager.default.copyItem(at: StudioFiles.repositoryContentURL, to: target)
        let history = try StudioFiles.historyURL(in: target)
        if FileManager.default.fileExists(atPath: history.path) { try FileManager.default.removeItem(at: history) }
        return target
    }

    @Test @MainActor func galleryLoadsTitlesUsingCatalogSortTitles() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let store = StudioStore(contentURL: target)
        await store.loadContent()
        #expect(store.errorMessage == nil)
        store.category = .movies
        let titles = store.visibleItems.map(\.title)
        let general = try #require(titles.firstIndex(of: "The General"))
        let metropolis = try #require(titles.firstIndex(of: "Metropolis"))
        let sherlock = try #require(titles.firstIndex(of: "Sherlock Jr."))
        let star = try #require(titles.firstIndex(of: "A Star Is Born"))
        #expect(general < metropolis)
        #expect(sherlock < star)
        #expect(store.items.filter { $0.category == .users }.allSatisfy { $0.sortTitle == nil })
        #expect(store.pack?.records.filter(\.isTitle).allSatisfy { $0.metadata["titleSort"]?.string != nil } == true)
    }

    @Test func contentSaveKeepsCatalogAndDecisionTogether() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        var pack = try StudioFiles.loadPack(at: target)
        var manifest = StudioManifest()
        var job = StudioJob(id: UUID(), title: "Reviewed title", kind: .catalog, prompt: "Research title", createdAt: Date())
        job.status = .accepted
        manifest.jobs = [job]
        pack.records[0].metadata["summary"] = .string("Reviewed summary")
        try StudioFiles.commitContent(pack, manifest: manifest, at: target, expected: StudioFiles.fingerprints(at: target))
        #expect(try StudioFiles.loadPack(at: target).records[0].metadata["summary"] == .string("Reviewed summary"))
        #expect(try StudioFiles.loadManifest(at: StudioFiles.historyURL(in: target)).jobs.first?.status == .accepted)
        let before = try StudioFiles.fingerprints(at: target)
        #expect(throws: (any Error).self) {
            try StudioFiles.commitContent(pack, manifest: manifest, at: target, expected: before, files: ["../escape.txt": Data()])
        }
        #expect(try StudioFiles.fingerprints(at: target) == before)
    }

    @Test func savingRejectsOutsideEditsAndPreservesOriginalFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        var pack = try StudioFiles.loadPack(at: target)
        let expected = try StudioFiles.fingerprints(at: target)
        pack.records[0].metadata["summary"] = .string("New summary")
        try Data("external change".utf8).write(to: target.appending(path: "external.txt"))
        #expect(throws: (any Error).self) {
            try StudioFiles.commitContent(pack, manifest: StudioManifest(), at: target, expected: expected)
        }
        #expect(try StudioFiles.loadPack(at: target).records[0].metadata["summary"] != .string("New summary"))
        let refreshed = try StudioFiles.fingerprints(at: target)
        try StudioFiles.commitContent(pack, manifest: StudioManifest(), at: target, expected: refreshed)
        #expect(try StudioFiles.loadPack(at: target).records[0].metadata["summary"] == .string("New summary"))
        #expect(try String(contentsOf: target.appending(path: "external.txt"), encoding: .utf8) == "external change")
    }

    @Test @MainActor func savedInstructionsSurviveReopeningAndNewGenerationsReadTheFile() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let instructionsURL = root.appending(path: "artwork-instructions.json")
        var initial = try StudioStore().loadArtworkInstructions()
        initial.avatar = "Initial artwork instructions."
        var saved = initial
        saved.avatar = "Watercolor with visible paper texture.\nUse muted colors."
        try initial.encoded().write(to: instructionsURL)
        let editor = StudioStore(contentURL: target, instructionsURL: instructionsURL)
        try editor.saveArtworkInstructions(saved, replacing: editor.loadArtworkInstructions())
        #expect(try editor.loadArtworkInstructions() == saved)
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: ".studio").path))

        let executable = try mockExecutable(in: root)
        let reopened = StudioStore(contentURL: target, instructionsURL: instructionsURL, codexExecutable: executable.path)
        await reopened.loadContent()
        #expect(try reopened.loadArtworkInstructions() == saved)
        let item = try #require(reopened.items.first { $0.category == .users })
        let reference = try #require(reopened.pack?.assets.first { $0.role == .avatar })
        let selectedFile = root.appending(path: "original-reference.png")
        let originalData = try StudioFiles.normalizedReference(at: StudioFiles.resolved(reference.resource, in: target))
        try originalData.write(to: selectedFile)
        let preview = try saved.prompt(item: item, role: .avatar, artDirection: "A friendly expression", revising: false)
        reopened.generate(item: item, role: .avatar, instructions: "A friendly expression", referencePath: "", referenceFileURL: selectedFile, expectedPrompt: preview)
        let firstPrompt = try #require(reopened.manifest.jobs.last?.prompt)
        #expect(firstPrompt == preview)
        #expect(firstPrompt.contains(saved.avatar))
        #expect(!firstPrompt.contains(saved.referenceArtwork))
        #expect(firstPrompt.contains("A friendly expression"))
        #expect(!firstPrompt.contains(initial.avatar))
        try await waitForGeneration(reopened)
        let firstJob = try #require(reopened.manifest.jobs.first)
        let directory = try StudioFiles.resolved(firstJob.directory, in: #require(reopened.historyURL))
        let submittedTurn = try JSONDecoder().decode(StudioJSON.self, from: Data(contentsOf: directory.appending(path: "submitted-turn.json")))
        let submittedThread = try JSONDecoder().decode(StudioJSON.self, from: Data(contentsOf: directory.appending(path: "submitted-thread.json")))
        #expect(submittedTurn["input"]?.array?.first?["text"]?.string == preview)
        #expect(submittedThread["developerInstructions"] == nil)
        let sentReference = try #require(submittedTurn["input"]?.array?.first(where: { $0["type"]?.string == "localImage" })?["path"]?.string)
        #expect(try Data(contentsOf: URL(fileURLWithPath: sentReference)) == originalData)

        // Changes made in an editor must also be used without restarting Studio.
        var external = saved
        external.avatar = "Pencil illustration on cream paper."
        try external.encoded().write(to: instructionsURL)
        #expect(reopened.generate(item: item, role: .avatar, instructions: "A friendly expression", referencePath: "", referenceFileURL: selectedFile, expectedPrompt: preview) == nil)
        #expect(reopened.manifest.jobs.count == 1)
        #expect(reopened.errorMessage?.contains("changed") == true)
        reopened.generate(item: item, role: .avatar, instructions: "A friendly expression", referencePath: reference.path)
        try await waitForGeneration(reopened)
        let history = try StudioFiles.loadManifest(at: #require(reopened.historyURL))
        #expect(history.jobs.count == 2)
        #expect(history.jobs.first?.prompt == firstPrompt)
        #expect(history.jobs.last?.prompt.contains(external.avatar) == true)
        #expect(history.jobs.last?.prompt.contains(saved.avatar) == false)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: #require(reopened.historyURL).appending(path: "studio.json"))) as? [String: Any]
        #expect(json?["style"] == nil)
        #expect((json?["jobs"] as? [[String: Any]])?.allSatisfy { $0["developerInstructions"] == nil } == true)
    }

    @MainActor private func waitForGeneration(_ store: StudioStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while store.hasActiveGenerations && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        if store.hasActiveGenerations { for job in store.manifest.jobs { store.cancelGeneration(job.id) } }
        try #require(!store.hasActiveGenerations, "Simulated generation did not finish")
    }

    @Test @MainActor func firstTVBackdropDoesNotReplaceItsPoster() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = try copyContent(to: root)
        var pack = try StudioFiles.loadPack(at: content)
        let recordIndex = try #require(pack.records.firstIndex { $0.type == "show" })
        let recordID = pack.records[recordIndex].id
        let posterPath = try #require(pack.records[recordIndex].metadata["thumb"]?.string)
        let referencePath = try #require(pack.records[recordIndex].metadata["art"]?.string)
        let poster = try #require(pack.assets.first { $0.path == posterPath })
        let reference = try #require(pack.assets.first { $0.path == referencePath })
        let posterURL = try StudioFiles.resolved(poster.resource, in: content)
        let originalPoster = try Data(contentsOf: posterURL)
        pack.records[recordIndex].metadata["art"] = nil
        try StudioFiles.savePack(pack, at: content)

        let executable = try mockExecutable(in: root, artwork: true)
        let store = StudioStore(contentURL: content, codexExecutable: executable.path)
        await store.loadContent()
        let item = try #require(store.items.first { $0.recordID == recordID })
        let jobID = try #require(store.generate(item: item, role: .backdrop, instructions: "",
            referencePath: "", referenceFileURL: StudioFiles.resolved(reference.resource, in: content)))
        try await waitForGeneration(store)
        let candidate = try #require(store.manifest.candidates.first { $0.jobID == jobID })
        try #require(candidate.assetPath != posterPath)
        #expect(candidate.assetPath == "/mock/art/studio/\(recordID)/backdrop.jpg")
        #expect(store.decide(candidate, accept: true))
        let saved = try StudioFiles.loadPack(at: content)
        let savedRecord = try #require(saved.records.first { $0.id == recordID })
        #expect(savedRecord.metadata["thumb"]?.string == posterPath)
        #expect(savedRecord.metadata["art"]?.string == candidate.assetPath)
        #expect(try Data(contentsOf: posterURL) == originalPoster)
    }

    @Test @MainActor func artworkJobIdentityTracksReviewRevisionAndAcceptance() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let executable = try mockExecutable(in: root, artwork: true)
        let store = StudioStore(contentURL: target, codexExecutable: executable.path)
        await store.loadContent()
        let before = try StudioFiles.fingerprints(at: target)
        let item = try #require(store.items.first { $0.category == .users })
        let reference = try #require(item.assetPath)
        let id = try #require(store.generate(item: item, role: .avatar, instructions: "Keep the hat", referencePath: reference))
        #expect(store.manifest.jobs.first { $0.id == id }?.status == .running)
        try await waitForGeneration(store)
        #expect(store.manifest.jobs.first { $0.id == id }?.status == .review)
        let candidate = try #require(store.manifest.candidates.first { $0.jobID == id })
        #expect(try StudioFiles.fingerprints(at: target) == before)

        let revisedID = try #require(store.generate(item: item, role: .avatar, instructions: "Make the hat blue", referencePath: reference, revising: candidate))
        #expect(revisedID != id)
        try await waitForGeneration(store)
        let revisedJob = try #require(store.manifest.jobs.first { $0.id == revisedID })
        #expect(revisedJob.status == .review)
        #expect(revisedJob.artwork?.references.count == 2)
        #expect(revisedJob.threadID != store.manifest.jobs.first { $0.id == id }?.threadID)
        #expect(revisedJob.prompt.contains("Make the hat blue"))
        let revised = try #require(store.manifest.candidates.first { $0.jobID == revisedID })
        #expect(store.decide(revised, accept: true))
        #expect(store.manifest.jobs.first { $0.id == revisedID }?.status == .accepted)
        #expect(store.manifest.candidates.first { $0.jobID == revisedID }?.decision == .accepted)
    }

    @Test @MainActor func artworkFailuresRemainOnTheJobAndCanBeRetried() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let executable = try mockExecutable(in: root, fail: true)
        let store = StudioStore(contentURL: target, codexExecutable: executable.path)
        await store.loadContent()
        let item = try #require(store.items.first { $0.category == .users })
        let reference = try #require(item.assetPath)
        let failedID = try #require(store.generate(item: item, role: .avatar, instructions: "Keep the hat", referencePath: reference))
        try await waitForGeneration(store)
        let failed = try #require(store.manifest.jobs.first { $0.id == failedID })
        #expect(failed.status == .failed)
        #expect(failed.message == "Test image generation failed.")
        #expect(store.errorMessage == nil)
        #expect(store.manifest.candidates.isEmpty)

        _ = try mockExecutable(in: root, artwork: true)
        let retryID = try #require(store.generate(item: item, role: .avatar, instructions: "Keep the hat", referencePath: reference))
        try await waitForGeneration(store)
        #expect(retryID != failedID)
        #expect(store.manifest.jobs.first { $0.id == retryID }?.status == .review)
        #expect(store.manifest.jobs.first { $0.id == failedID }?.status == .failed)
    }

    @Test @MainActor func stoppingArtworkLeavesAnInterruptedJobAndNoCandidate() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let executable = try mockExecutable(in: root, complete: false)
        let store = StudioStore(contentURL: target, codexExecutable: executable.path)
        await store.loadContent()
        let item = try #require(store.items.first { $0.category == .users })
        let reference = try #require(item.assetPath)
        let id = try #require(store.generate(item: item, role: .avatar, instructions: "", referencePath: reference))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while store.manifest.jobs.first?.threadID == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        store.cancelGeneration(id)
        try await waitForGeneration(store)
        #expect(store.manifest.jobs.first { $0.id == id }?.status == .interrupted)
        #expect(store.manifest.jobs.first { $0.id == id }?.message == "Generation stopped.")
        #expect(store.manifest.candidates.isEmpty)
        #expect(store.errorMessage == nil)
        #expect(store.generations.runtimes.isEmpty)
    }

    @Test @MainActor func instructionSavesRejectConflictsAndEmptyInputWithoutOverwritingTheFile() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "artwork-instructions.json")
        let initial = try StudioStore().loadArtworkInstructions()
        try initial.encoded().write(to: url)
        let store = StudioStore(instructionsURL: url)
        let original = try store.loadArtworkInstructions()
        var blank = original
        blank.referenceArtwork = " \n"
        #expect(throws: (any Error).self) { try store.saveArtworkInstructions(blank, replacing: original) }
        #expect(try store.loadArtworkInstructions() == original)
        var external = original
        external.referenceArtwork = "External edit"
        try external.encoded().write(to: url)
        #expect(throws: (any Error).self) { try store.saveArtworkInstructions(original, replacing: original) }
        #expect(try store.loadArtworkInstructions() == external)
        // Empty sections remain editable so they can be corrected in Settings.
        try blank.encoded().write(to: url)
        try store.saveArtworkInstructions(original, replacing: store.loadArtworkInstructions())
        #expect(try store.loadArtworkInstructions() == original)
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) { try store.loadArtworkInstructions() }
        #expect(throws: (any Error).self) { try store.saveArtworkInstructions(original, replacing: original) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test @MainActor func artworkPromptsUseTwoTemplatesAndTypeSpecificDimensions() throws {
        let instructions = try StudioStore().loadArtworkInstructions()
        let item = StudioGalleryItem(id: "test", title: "Example", subtitle: "Test subject", category: .movies, ratio: 1)
        let expectedSizes: [StudioArtworkRole: String] = [.avatar: "1024x1024", .poster: "1024x1536", .cover: "1024x1024", .backdrop: "1536x864"]
        for role in StudioArtworkRole.allCases {
            let prompt = try instructions.prompt(item: item, role: role, artDirection: "Keep the hat", revising: true)
            #expect(prompt.contains(instructions.avatar) == (role == .avatar))
            #expect(prompt.contains(instructions.referenceArtwork) == (role != .avatar))
            #expect(prompt.contains(try #require(expectedSizes[role])))
            #expect(prompt.contains("Requested revision:\nKeep the hat"))
            #expect(prompt.contains("Image 2 is the previous candidate."))
        }
        let newArtwork = try instructions.prompt(item: item, role: .poster, artDirection: "", revising: false)
        #expect(!newArtwork.contains("Image 2"))
        #expect(!newArtwork.contains("Additional instructions:"))
        let json = try #require(JSONSerialization.jsonObject(with: instructions.encoded()) as? [String: Any])
        #expect(Set(json.keys) == ["avatar", "referenceArtwork"])
    }

    @Test @MainActor func pendingDraftsPersistWithoutChangingAcceptedContent() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let before = try StudioFiles.fingerprints(at: target)
        let store = StudioStore(contentURL: target)
        await store.loadContent()
        #expect(store.packURL == target)
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: ".studio").path))
        var manifest = StudioManifest()
        var job = StudioJob(id: UUID(), title: "Draft", kind: .catalog, prompt: "Test", createdAt: Date())
        job.status = .review
        manifest.jobs = [job]
        try StudioFiles.saveHistory(manifest, at: StudioFiles.historyURL(in: target), files: ["candidates/draft.txt": Data("draft".utf8)])
        #expect(try StudioFiles.fingerprints(at: target) == before)
        await store.loadContent()
        #expect(store.manifest.jobs.first?.status == .review)
        #expect(store.manifest.jobs.first?.id == job.id)
    }

    @Test func titleCompilationCreatesDeterministicHierarchyAndRejectsInvalidDrafts() throws {
        let pack = try StudioFiles.loadPack(at: StudioFiles.repositoryContentURL)
        let draft = StudioTitleDraft(notes: "Test", records: [
            .init(localID: "show", type: "show", title: "Example show", summary: "Example", sources: ["https://example.com/show"], genres: []),
            .init(localID: "season", parentLocalID: "show", type: "season", title: "Season 1", summary: "Example", index: 1, sources: ["https://example.com/show"], genres: []),
            .init(localID: "episode", parentLocalID: "season", type: "episode", title: "Episode 1", durationMilliseconds: 120000, summary: "Example", index: 1, sources: ["https://example.com/show"], genres: [])
        ])
        let compiled = try draft.compile(into: pack)
        #expect(compiled.pack.validate().isEmpty)
        let show = try #require(compiled.pack.records.first { $0.id == compiled.titleID })
        #expect(show.metadata["childCount"]?.integer == 1)
        #expect(show.metadata["leafCount"]?.integer == 1)
        #expect(try draft.compile(into: pack).titleID == compiled.titleID)
        var invalid = draft
        invalid.records[2].parentLocalID = "missing"
        #expect(throws: (any Error).self) { try invalid.compile(into: pack) }
        invalid = draft
        invalid.records[0].parentLocalID = "episode"
        #expect(throws: (any Error).self) { try invalid.compile(into: pack) }
        invalid = draft
        invalid.records.append(.init(localID: "unrelated", type: "artist", title: "Unrelated", summary: "", sources: ["https://example.com"], genres: []))
        #expect(throws: (any Error).self) { try invalid.compile(into: pack) }
    }

    @Test func exportsCorrectImageDimensionsAndRejectsWrongAspectRatio() throws {
        let pack = try StudioFiles.loadPack(at: StudioFiles.repositoryContentURL)
        let asset = try #require(pack.assets.first { $0.role == .avatar })
        let original = try Data(contentsOf: StudioFiles.resolved(asset.resource, in: StudioFiles.repositoryContentURL))
        let exported = try StudioFiles.exportImage(original, role: .avatar)
        let source = try #require(CGImageSourceCreateWithData(exported as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 360 && image.height == 360)
        #expect(throws: (any Error).self) { try StudioFiles.exportImage(original, role: .poster) }
    }

    @Test @MainActor func protocolHandlesFragmentedUnicodeAndMultipleMessages() throws {
        let connection = StudioCodexConnection()
        var values: [String] = []
        connection.onNotification = { _, payload in values.append(payload["delta"]?.string ?? "") }
        let bytes = Data("{\"method\":\"item/agentMessage/delta\",\"params\":{\"delta\":\"Clay 🎨\"}}\n{\"method\":\"item/agentMessage/delta\",\"params\":{\"delta\":\"Done\"}}\n".utf8)
        for byte in bytes { try connection.receive(Data([byte])) }
        #expect(values == ["Clay 🎨", "Done"])
        #expect(throws: (any Error).self) { try connection.receive(Data("not json\n".utf8)) }
    }

    private func mockExecutable(in root: URL, complete: Bool = true, authenticated: Bool = true, images: Bool = true, artwork: Bool = false, fail: Bool = false) throws -> URL {
        let url = root.appending(path: "codex-mock")
        let script = """
        #!/usr/bin/python3
        import json, sys, os
        def send(value):
            print(json.dumps(value), flush=True)
        initialized = False
        for line in sys.stdin:
            request = json.loads(line)
            method = request.get('method')
            params = request.get('params', {})
            if method == 'initialized':
                initialized = True
                continue
            result = {}
            if method == 'initialize':
                result = {'userAgent': 'codex/1.2.3 (test)'}
            elif not initialized:
                sys.exit(2)
            elif method == 'account/read':
                result = {'account': {'type': 'chatgpt', 'email': 'studio@example.com'} if \(authenticated ? "True" : "False") else None, 'requiresOpenaiAuth': True}
            elif method == 'modelProvider/capabilities/read':
                result = {'imageGeneration': \(images ? "True" : "False"), 'webSearch': True, 'namespaceTools': True}
            elif method in ('thread/start', 'thread/resume'):
                with open('submitted-thread.json', 'w') as capture:
                    json.dump(params, capture)
                result = {'thread': {'id': params.get('threadId', os.path.basename(os.getcwd()))}, 'model': 'test-model'}
            elif method == 'turn/start':
                with open('submitted-turn.json', 'w') as capture:
                    json.dump(params, capture)
                result = {'turn': {'id': 'test-turn', 'status': 'inProgress'}}
                if \(complete ? "True" : "False"):
                    # Deliberately complete before acknowledging turn/start.
                    if \(artwork ? "True" : "False"):
                        reference = next(i['path'] for i in params['input'] if i['type'] == 'localImage')
                        send({'method': 'item/completed', 'params': {'threadId': params['threadId'], 'item': {'type': 'imageGeneration', 'status': 'completed', 'savedPath': reference}}})
                    send({'method': 'item/completed', 'params': {'threadId': params['threadId'], 'item': {'type': 'agentMessage', 'text': 'draft result', 'phase': 'final_answer'}}})
                    send({'method': 'turn/completed', 'params': {'threadId': params['threadId'], 'turn': {'id': 'test-turn', 'status': 'failed' if \(fail ? "True" : "False") else 'completed', 'error': {'message': 'Test image generation failed.'}}}})
            elif method == 'turn/interrupt':
                send({'method': 'turn/completed', 'params': {'threadId': params['threadId'], 'turn': {'id': 'test-turn', 'status': 'interrupted'}}})
            elif method == 'exit-now':
                sys.exit(4)
            send({'id': request['id'], 'result': result})
        """
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test @MainActor func appServerLifecycleRetainsEarlyCompletionAndResumesThread() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try mockExecutable(in: root)
        let engine = StudioCodexEngine()
        var savedThread = ""
        let result = try await engine.run(executable: executable.path, directory: root, prompt: "test", threadID: "existing-thread") { thread, _ in savedThread = thread }
        #expect(savedThread == "existing-thread")
        #expect(result.threadID == "existing-thread")
        #expect(result.text == "draft result")
        #expect(!engine.isRunning)
    }

    @Test @MainActor func codexStatusReportsAccountVersionAndClearsStaleDetails() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try mockExecutable(in: root)
        let status = StudioCodexStatusStore()
        await status.check(executable: executable.path, directory: root)
        #expect(status.status == .ready)
        #expect(status.account == "studio@example.com")
        #expect(status.version == "1.2.3")
        #expect(status.message == nil)

        let cancelled = Task { await status.check(executable: executable.path, directory: root) }
        cancelled.cancel()
        await cancelled.value
        #expect(status.status == .ready)
        #expect(status.account == "studio@example.com")

        await status.check(executable: root.appending(path: "missing-codex").path, directory: root)
        #expect(status.status == .unavailable)
        #expect(status.account == nil)
        #expect(status.version == nil)
        #expect(status.message?.contains("missing-codex") == true)

        await status.check(executable: executable.path, directory: root)
        #expect(status.status == .ready)
        #expect(status.account == "studio@example.com")
        #expect(status.message == nil)
    }

    @Test @MainActor func codexStatusDistinguishesSignInFromMissingImageGeneration() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let status = StudioCodexStatusStore()
        let signedOut = try mockExecutable(in: root, authenticated: false)
        await status.check(executable: signedOut.path, directory: root)
        #expect(status.status == .needsAttention)
        #expect(status.account == "Not signed in with ChatGPT")
        #expect(status.message?.contains("Sign in") == true)

        let noImages = try mockExecutable(in: root, images: false)
        await status.check(executable: noImages.path, directory: root)
        #expect(status.status == .needsAttention)
        #expect(status.account == "studio@example.com")
        #expect(status.version == "1.2.3")
        #expect(status.message?.contains("image generation") == true)
    }

    @Test @MainActor func processExitFailsPendingRequestWithoutHanging() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try mockExecutable(in: root)
        let connection = StudioCodexConnection()
        defer { connection.stop() }
        try await connection.start(executable: executable.path, cwd: root)
        await #expect(throws: (any Error).self) { try await connection.request("exit-now") }
        #expect(!connection.isRunning)
    }

    @Test @MainActor func cancellingAnActiveJobClosesItsOwnedProcess() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try mockExecutable(in: root, complete: false)
        let engine = StudioCodexEngine()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let task = Task {
            try await engine.run(executable: executable.path, directory: root, prompt: "test") { _, _ in signal.yield(()) }
        }
        for await _ in started { break }
        task.cancel()
        do { _ = try await task.value; Issue.record("The cancelled job unexpectedly completed.") }
        catch { #expect(error is CancellationError) }
        #expect(!engine.isRunning)
    }

    @Test @MainActor func acceptanceRejectsTamperedCandidateWithoutChangingContent() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let store = StudioStore(contentURL: target)
        await store.loadContent()
        let pack = try #require(store.pack)
        let asset = try #require(pack.assets.first { $0.role == .avatar })
        let candidate = StudioCandidate(id: UUID(), title: "Test", assetPath: asset.path, role: .avatar,
            file: "candidates/test.png", prompt: "test", model: "test", jobID: UUID(), referenceHashes: [],
            outputHash: "different-hash", createdAt: Date(), decision: .pending)
        store.manifest.candidates = [candidate]
        try StudioFiles.saveHistory(store.manifest, at: #require(store.historyURL), files: [candidate.file: Data("tampered".utf8)])
        let before = try StudioFiles.fingerprints(at: target)
        store.decide(candidate, accept: true)
        #expect(store.errorMessage?.contains("changed") == true)
        #expect(store.manifest.candidates[0].decision == .pending)
        #expect(try StudioFiles.fingerprints(at: target) == before)
    }

    @Test @MainActor func acceptingArtworkSavesToContentAndPersistsDecision() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let store = StudioStore(contentURL: target)
        await store.loadContent()
        let pack = try #require(store.pack)
        let asset = try #require(pack.assets.first { $0.role == .avatar })
        let data = try Data(contentsOf: StudioFiles.resolved(asset.resource, in: target))
        let candidate = StudioCandidate(id: UUID(), title: "Test", assetPath: asset.path, role: .avatar,
            file: "candidates/test.png", prompt: "test", model: "test", jobID: UUID(), referenceHashes: [],
            outputHash: StudioFiles.hash(data), createdAt: Date(), decision: .pending)
        store.manifest.candidates = [candidate]
        try StudioFiles.saveHistory(store.manifest, at: #require(store.historyURL), files: [candidate.file: data])
        store.decide(candidate, accept: true)
        #expect(store.errorMessage == nil)
        #expect(store.manifest.candidates.first?.decision == .accepted)
        #expect(try Data(contentsOf: StudioFiles.resolved(asset.resource, in: target)) == StudioFiles.exportImage(data, role: .avatar))
        await store.loadContent()
        #expect(store.manifest.candidates.first?.decision == .accepted)
    }

    @Test @MainActor func metadataEditsSaveDirectlyAndConflictsLeaveMemoryUnchanged() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let store = StudioStore(contentURL: target)
        await store.loadContent()
        let record = try #require(store.pack?.records.first)
        var metadata = record.metadata
        metadata["summary"] = .string("Edited and saved")
        try store.applyMetadataJSON(metadata.prettyPrinted, recordID: record.id)
        #expect(try StudioFiles.loadPack(at: target).records[0].metadata["summary"] == .string("Edited and saved"))
        try Data("outside edit".utf8).write(to: target.appending(path: "outside.txt"))
        metadata["summary"] = .string("Conflicting edit")
        #expect(throws: (any Error).self) { try store.applyMetadataJSON(metadata.prettyPrinted, recordID: record.id) }
        #expect(store.pack?.records[0].metadata["summary"] == .string("Edited and saved"))
        #expect(try StudioFiles.loadPack(at: target).records[0].metadata["summary"] == .string("Edited and saved"))
    }

    @Test @MainActor func userEditsSaveProfilesAndLeaveActivityReferencesIntact() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let store = StudioStore(contentURL: target)
        await store.loadContent()
        let original = try store.userProfile(id: 12)
        let originalSessions = store.pack?.payload["activeSessions"]
        let originalHistory = store.pack?.payload["historyEvents"]
        var user = original
        user.friendlyName = "Edited Elliot"
        user.email = "edited@example.com"
        user.avatar = try store.userProfile(id: 16).avatar
        user.devices[0].title = "Firefox"
        user.devices[0].connection.resolvedLocation = "Queens, NY"
        try store.saveUser(user, replacing: original, signedIn: true, originalAuthenticatedUserID: 16)
        await store.loadContent()
        #expect(try store.userProfile(id: 12) == user)
        #expect(store.pack?.payload["authenticatedUserID"]?.integer == 12)
        #expect(store.pack?.payload["activeSessions"] == originalSessions)
        #expect(store.pack?.payload["historyEvents"] == originalHistory)
        #expect(store.items.first { $0.id == "user:12" }?.title == "Edited Elliot")
        #expect(store.items.first { $0.id == "user:12" }?.category == .users)
        var renamed = user
        renamed.friendlyName = nil
        renamed.username = "elliot-new"
        try store.saveUser(renamed, replacing: user, signedIn: true, originalAuthenticatedUserID: 12)
        await store.loadContent()
        #expect(store.items.first { $0.id == "user:12" }?.title == "elliot-new")
        #expect(try store.userProfile(id: 12).materializeAuthenticatedUser().title == "elliot-new")
    }

    @Test @MainActor func userEditsRejectReferencedDeviceRemovalAndConflictingSaves() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let store = StudioStore(contentURL: target)
        await store.loadContent()
        let original = try store.userProfile(id: 12)
        var invalid = original
        invalid.devices = []
        let before = try StudioFiles.fingerprints(at: target)
        #expect(throws: (any Error).self) {
            try store.saveUser(invalid, replacing: original, signedIn: false, originalAuthenticatedUserID: 16)
        }
        #expect(try store.userProfile(id: 12) == original)
        #expect(try StudioFiles.fingerprints(at: target) == before)
        var changed = original
        changed.friendlyName = "Changed"
        try Data("outside edit".utf8).write(to: target.appending(path: "outside.txt"))
        #expect(throws: (any Error).self) {
            try store.saveUser(changed, replacing: original, signedIn: false, originalAuthenticatedUserID: 16)
        }
        #expect(try store.userProfile(id: 12) == original)
    }

    @Test @MainActor func parallelFirstAvatarsCanReplaceAfterReviewingTheCurrentDestination() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let executable = try mockExecutable(in: root, artwork: true)
        let store = StudioStore(contentURL: target, codexExecutable: executable.path)
        await store.loadContent()
        let original = try store.userProfile(id: 12)
        let reference = try #require(original.avatar)
        var user = original
        user.avatar = nil
        try store.saveUser(user, replacing: original, signedIn: false, originalAuthenticatedUserID: 16)
        let item = try #require(store.items.first { $0.id == "user:12" })
        let ids = try (0..<3).map { _ in
            try #require(store.generate(item: item, role: .avatar, instructions: "", referencePath: reference))
        }
        try await waitForGeneration(store)
        let candidates = try ids.map { id in try #require(store.manifest.candidates.first { $0.jobID == id }) }
        #expect(candidates.allSatisfy { $0.assetPath == candidates[0].assetPath })
        #expect(ids.allSatisfy { id in store.manifest.jobs.first { $0.id == id }?.artwork?.userAvatarPath == nil })
        #expect(store.decide(candidates[0], accept: true))
        await store.loadContent()
        #expect(store.needsReplacementConfirmation(candidates[1]))
        let before = try StudioFiles.fingerprints(at: target)
        #expect(!store.decide(candidates[1], accept: true))
        #expect(try StudioFiles.fingerprints(at: target) == before)
        let reviewed = try store.destinationSnapshot(path: candidates[1].assetPath)
        #expect(store.decide(candidates[1], accept: true, replacing: reviewed))
        let after = try StudioFiles.fingerprints(at: target)
        #expect(!store.decide(candidates[2], accept: true, replacing: reviewed))
        #expect(try StudioFiles.fingerprints(at: target) == after)
        let current = try store.destinationSnapshot(path: candidates[2].assetPath)
        #expect(store.decide(candidates[2], accept: true, replacing: current))
        await store.loadContent()
        #expect(try store.userProfile(id: 12).avatar == candidates[2].assetPath)
        #expect(try store.destinationSnapshot(path: candidates[2].assetPath).acceptedCandidateID == candidates[2].id)
    }

    @Test(arguments: [false, true]) @MainActor
    func generatedAvatarsAttachToUsersUnlessTheirSelectionChanged(changeSelection: Bool) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try copyContent(to: root)
        let executable = try mockExecutable(in: root, artwork: true)
        let store = StudioStore(contentURL: target, codexExecutable: executable.path)
        await store.loadContent()
        let original = try store.userProfile(id: 12)
        let reference = try #require(original.avatar)
        var user = original
        user.avatar = nil
        try store.saveUser(user, replacing: original, signedIn: false, originalAuthenticatedUserID: 16)
        let item = try #require(store.items.first { $0.id == "user:12" })
        let jobID = try #require(store.generate(item: item, role: .avatar, instructions: "", referencePath: reference))
        try await waitForGeneration(store)
        let candidate = try #require(store.manifest.candidates.first { $0.jobID == jobID })
        #expect(candidate.userID == 12)
        #expect(candidate.assetPath == "/mock/avatars/elliot.png")
        if changeSelection {
            var changed = user
            changed.avatar = reference
            try store.saveUser(changed, replacing: user, signedIn: false, originalAuthenticatedUserID: 16)
            let before = try StudioFiles.fingerprints(at: target)
            #expect(!store.decide(candidate, accept: true))
            #expect(store.errorMessage?.contains("avatar selection changed") == true)
            #expect(try store.userProfile(id: 12).avatar == reference)
            #expect(try StudioFiles.fingerprints(at: target) == before)
        } else {
            #expect(store.decide(candidate, accept: true))
            await store.loadContent()
            #expect(try store.userProfile(id: 12).avatar == candidate.assetPath)
            #expect(store.artworkURL(for: candidate.assetPath) != nil)
            #expect(store.pack?.validate().isEmpty == true)
        }
    }

}
