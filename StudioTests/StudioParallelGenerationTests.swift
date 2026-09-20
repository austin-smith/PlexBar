import Foundation
import Testing
@testable import PlexBarStudio

@Suite @MainActor struct StudioParallelGenerationTests {
    @MainActor private struct Fixture {
        let root: URL
        let content: URL
        let store: StudioStore
        let item: StudioGalleryItem
        let reference: String
        func directory(_ id: UUID) throws -> URL {
            try StudioFiles.resolved("jobs/\(id.uuidString)", in: #require(store.historyURL))
        }
        func signal(_ id: UUID, _ name: String) throws {
            try Data().write(to: directory(id).appending(path: name), options: .atomic)
        }
        func generate(_ instructions: String = "") throws -> UUID {
            try #require(store.generate(item: item, role: .avatar, instructions: instructions, referencePath: reference))
        }
        func cleanUp() async {
            await store.shutdownGenerations()
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: "studio-parallel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let content = root.appending(path: "MockServer")
        try FileManager.default.copyItem(at: StudioFiles.repositoryContentURL, to: content)
        let history = try StudioFiles.historyURL(in: content)
        if FileManager.default.fileExists(atPath: history.path) { try FileManager.default.removeItem(at: history) }
        let executable = root.appending(path: "codex-test")
        try Data(Self.server.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let instructions = root.appending(path: "artwork-instructions.json")
        try FileManager.default.copyItem(at: StudioFiles.artworkInstructionsURL, to: instructions)
        let store = StudioStore(contentURL: content, instructionsURL: instructions, codexExecutable: executable.path)
        await store.loadContent()
        let item = try #require(store.items.first { $0.category == .users })
        return Fixture(root: root, content: content, store: store, item: item, reference: try #require(item.assetPath))
    }

    private func wait(_ condition: () throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while try !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(15)) }
        try #require(try condition(), "Timed out waiting for simulated Codex")
    }

    @Test func jobsQueueIndependentlyAndAcceptancePreservesAnotherProcessesOpenFiles() async throws {
        let f = try await fixture()
        do {
            let first = try f.generate("First request")
            let second = try f.generate("Second request")
            let additional = try (0..<4).map { try f.generate("Additional request \($0)") }
            let third = try f.generate("Queued request")
            #expect(f.store.generations.runtimes.count == 6)
            #expect(f.store.manifest.jobs.last?.status == .queued)
            try await wait { try ([first, second] + additional).allSatisfy { FileManager.default.fileExists(atPath: try f.directory($0).appending(path: "started").path) } }
            #expect(!FileManager.default.fileExists(atPath: try f.directory(third).appending(path: "started").path))
            try f.signal(first, "finish")
            try await wait { f.store.manifest.jobs.first { $0.id == first }?.status == .review }
            try await wait { try FileManager.default.fileExists(atPath: f.directory(third).appending(path: "started").path) }
            let candidate = try #require(f.store.manifest.candidates.first { $0.jobID == first })
            #expect(f.store.decide(candidate, accept: true))
            #expect(f.store.errorMessage == nil)
            #expect(f.store.manifest.jobs.first { $0.id == second }?.status == .running)
            // The second process holds this file open across both history and content saves.
            let live = try f.directory(second).appending(path: "live.txt")
            let before = try Data(contentsOf: live).count
            try await wait { try Data(contentsOf: live).count > before }
            try f.signal(second, "finish")
            try f.signal(third, "finish")
            for id in additional { try f.signal(id, "finish") }
            try await wait { !f.store.hasActiveGenerations }
            #expect(f.store.manifest.candidates.count == 7)
            let persisted = try StudioFiles.loadManifest(at: #require(f.store.historyURL))
            #expect(persisted.candidates.count == 7)
            #expect(persisted.jobs.filter { $0.status == .review }.count == 6)
            for job in persisted.jobs {
                let submitted = try String(contentsOf: f.directory(job.id).appending(path: "prompt.txt"), encoding: .utf8)
                #expect(submitted == job.prompt)
                #expect(FileManager.default.fileExists(atPath: try f.directory(job.id).appending(path: "generated.png").path))
            }
        } catch { await f.cleanUp(); throw error }
        await f.cleanUp()
    }

    @Test func stopAndFailureAffectOnlyTheirOwnJobs() async throws {
        let f = try await fixture()
        do {
            let first = try f.generate()
            let second = try f.generate()
            let additional = try (0..<4).map { _ in try f.generate() }
            let third = try f.generate()
            f.store.cancelGeneration(third)
            try await wait { f.store.manifest.jobs.first { $0.id == first }?.threadID != nil }
            f.store.cancelGeneration(first)
            try await wait { f.store.manifest.jobs.first { $0.id == first }?.status == .interrupted }
            #expect(f.store.manifest.jobs.first { $0.id == second }?.status == .running)
            #expect(f.store.manifest.jobs.first { $0.id == third }?.status == .interrupted)
            #expect(!FileManager.default.fileExists(atPath: try f.directory(third).appending(path: "started").path))
            try f.signal(second, "fail")
            for id in additional { f.store.cancelGeneration(id) }
            try await wait { !f.store.hasActiveGenerations }
            #expect(f.store.manifest.jobs.first { $0.id == second }?.message == "Test failure")
            #expect(f.store.errorMessage == nil)
        } catch { await f.cleanUp(); throw error }
        await f.cleanUp()
    }

    @Test func approvalsWithIdenticalRPCIDsRemainScopedToTheirJob() async throws {
        let f = try await fixture()
        do {
            let first = try f.generate()
            let second = try f.generate()
            try f.signal(first, "ask")
            try f.signal(second, "ask")
            try await wait { [first, second].allSatisfy { f.store.generations.runtimes[$0]?.engine.approvals.count == 1 } }
            let engine = try #require(f.store.generations.runtimes[first]?.engine)
            engine.answer(try #require(engine.approvals.first), allow: true)
            try await wait { try FileManager.default.fileExists(atPath: f.directory(first).appending(path: "approved").path) }
            #expect(f.store.generations.runtimes[second]?.engine.approvals.count == 1)
            #expect(!FileManager.default.fileExists(atPath: try f.directory(second).appending(path: "approved").path))
            try f.signal(first, "finish")
            try await wait { f.store.manifest.jobs.first { $0.id == first }?.status == .review }
            #expect(f.store.generations.runtimes[second]?.engine.approvals.count == 1)
        } catch { await f.cleanUp(); throw error }
        await f.cleanUp()
    }

    @Test func replacingNewlyAcceptedArtworkRequiresAnExactReviewedDestination() async throws {
        let f = try await fixture()
        do {
            let first = try f.generate()
            let second = try f.generate()
            try f.signal(first, "finish")
            try f.signal(second, "finish")
            try await wait { !f.store.hasActiveGenerations }
            let a = try #require(f.store.manifest.candidates.first { $0.jobID == first })
            let b = try #require(f.store.manifest.candidates.first { $0.jobID == second })
            let stale = try f.store.destinationSnapshot(path: a.assetPath)
            #expect(f.store.decide(a, accept: true))
            #expect(f.store.needsReplacementConfirmation(b))
            #expect(!f.store.decide(b, accept: true))
            #expect(!f.store.decide(b, accept: true, replacing: stale))
            let current = try f.store.destinationSnapshot(path: b.assetPath)
            #expect(f.store.decide(b, accept: true, replacing: current), "Replacement failed: \(f.store.errorMessage ?? "unknown")")
            #expect(try f.store.destinationSnapshot(path: b.assetPath).acceptedCandidateID == b.id)
        } catch { await f.cleanUp(); throw error }
        await f.cleanUp()
    }

    @Test func relaunchRecoversRunningAndQueuedJobsWithoutSubmittingThem() async throws {
        let f = try await fixture()
        do {
            var manifest = StudioManifest()
            var running = StudioJob(id: UUID(), title: "Running", kind: .artwork, prompt: "one", createdAt: Date())
            running.status = .running
            manifest.jobs = [running, StudioJob(id: UUID(), title: "Queued", kind: .artwork, prompt: "two", createdAt: Date())]
            try StudioFiles.saveManifest(manifest, at: #require(f.store.historyURL))
            await f.store.loadContent()
            #expect(f.store.manifest.jobs.allSatisfy { $0.status == .interrupted })
            #expect(f.store.generations.runtimes.isEmpty)
            #expect(try StudioFiles.loadManifest(at: #require(f.store.historyURL)).jobs.allSatisfy { $0.status == .interrupted })
        } catch { await f.cleanUp(); throw error }
        await f.cleanUp()
    }

    @Test func queuedRequestsRetainTheirPromptAndReferenceWhenInputsChange() async throws {
        let f = try await fixture()
        do {
            let first = try f.generate()
            let others = try (0..<5).map { _ in try f.generate() }
            let queued = try f.generate("Keep this request")
            #expect(f.store.manifest.jobs.last?.status == .queued)
            let job = try #require(f.store.manifest.jobs.first { $0.id == queued })
            let reference = try Data(contentsOf: f.directory(queued).appending(path: "reference-1.png"))
            let original = try f.store.loadArtworkInstructions()
            var edited = original
            edited.avatar = "Different instructions"
            try f.store.saveArtworkInstructions(edited, replacing: original)
            try FileManager.default.removeItem(at: #require(f.store.artworkURL(for: f.reference)))
            f.store.cancelGeneration(first)
            try await wait { try FileManager.default.fileExists(atPath: f.directory(queued).appending(path: "started").path) }
            #expect(try String(contentsOf: f.directory(queued).appending(path: "prompt.txt"), encoding: .utf8) == job.prompt)
            #expect(try Data(contentsOf: f.directory(queued).appending(path: "reference-1.png")) == reference)
            try f.signal(queued, "finish")
            for id in others { f.store.cancelGeneration(id) }
            try await wait { !f.store.hasActiveGenerations }
            #expect(f.store.manifest.jobs.first { $0.id == queued }?.status == .review)
        } catch { await f.cleanUp(); throw error }
        await f.cleanUp()
    }

    @Test func shutdownStopsActiveJobsWithoutLaunchingQueuedWork() async throws {
        let f = try await fixture()
        do {
            for _ in 0..<6 { _ = try f.generate() }
            let queued = try f.generate()
            await f.store.shutdownGenerations()
            #expect(f.store.generations.runtimes.isEmpty)
            #expect(f.store.manifest.jobs.allSatisfy { $0.status == .interrupted })
            #expect(!FileManager.default.fileExists(atPath: try f.directory(queued).appending(path: "started").path))
            #expect(try StudioFiles.loadManifest(at: #require(f.store.historyURL)).jobs.allSatisfy { $0.status == .interrupted })
        } catch { await f.cleanUp(); throw error }
        await f.cleanUp()
    }

    @Test func revisionsMoveEarlierVersionsToHistoryAndPreserveDecisions() async throws {
        let f = try await fixture()
        do {
            let original = try f.generate()
            let independent = try f.generate()
            try f.signal(original, "finish")
            try f.signal(independent, "finish")
            try await wait { !f.store.hasActiveGenerations }
            let candidate = try #require(f.store.manifest.candidates.first { $0.jobID == original })
            let revisionID = try #require(f.store.generate(item: f.item, role: .avatar,
                instructions: "More clay-like", referencePath: f.reference, revising: candidate))
            let revision = try #require(f.store.manifest.jobs.first { $0.id == revisionID })
            let source = try #require(f.store.manifest.jobs.first { $0.id == original })
            #expect(f.store.sourceGeneration(for: revision)?.id == original)
            #expect(f.store.revisions(of: source).map(\.id) == [revisionID])
            #expect(f.store.generationFilter(for: source) == .history)
            #expect(f.store.generationActionTitle(for: source) == nil)
            #expect(f.store.generationJobs(in: .attention).map(\.id) == [independent])
            #expect(f.store.manifest.candidates.first { $0.id == candidate.id }?.decision == .pending)
            try f.signal(revisionID, "fail")
            try await wait { !f.store.hasActiveGenerations }
            #expect(Set(f.store.generationJobs(in: .attention).map(\.id)) == [revisionID, independent])
            f.store.resume(try #require(f.store.manifest.jobs.first { $0.id == revisionID }))
            try FileManager.default.removeItem(at: f.directory(revisionID).appending(path: "fail"))
            try f.signal(revisionID, "finish")
            try await wait { !f.store.hasActiveGenerations }
            #expect(f.store.manifest.jobs.first { $0.id == revisionID }?.status == .review)
            let revised = try #require(f.store.manifest.candidates.first { $0.jobID == revisionID })
            let next = try #require(f.store.generate(item: f.item, role: .avatar,
                instructions: "Simplify", referencePath: f.reference, revising: revised))
            f.store.cancelGeneration(next)
            try await wait { !f.store.hasActiveGenerations }
            await f.store.loadContent()
            #expect(Set(f.store.generationJobs(in: .history).map(\.id)) == [original, revisionID])
            #expect(Set(f.store.generationJobs(in: .attention).map(\.id)) == [next, independent])
            let restored = try #require(f.store.manifest.jobs.first { $0.id == next })
            #expect(f.store.sourceGeneration(for: restored)?.id == revisionID)
            #expect(f.store.decide(candidate, accept: true))
            #expect(f.store.manifest.jobs.first { $0.id == original }?.status == .accepted)
            #expect(f.store.manifest.candidates.first { $0.id == revised.id }?.decision == .pending)
        } catch { await f.cleanUp(); throw error }
        await f.cleanUp()
    }

    @Test func unsuccessfulRevisionSubmissionLeavesOriginalNeedingAttention() async throws {
        let f = try await fixture()
        do {
            let original = try f.generate()
            try f.signal(original, "finish")
            try await wait { !f.store.hasActiveGenerations }
            let candidate = try #require(f.store.manifest.candidates.first { $0.jobID == original })
            let manifestURL = try #require(f.store.historyURL).appending(path: "studio.json")
            let saved = try Data(contentsOf: manifestURL)
            try FileManager.default.removeItem(at: manifestURL)
            try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: false)
            let revision = f.store.generate(item: f.item, role: .avatar,
                instructions: "Revise", referencePath: f.reference, revising: candidate)
            try FileManager.default.removeItem(at: manifestURL)
            try saved.write(to: manifestURL, options: .atomic)
            #expect(revision == nil)
            #expect(f.store.errorMessage != nil)
            #expect(f.store.manifest.jobs.count == 1)
            #expect(f.store.generationJobs(in: .attention).map(\.id) == [original])
            #expect(f.store.generations.runtimes.isEmpty)
        } catch { await f.cleanUp(); throw error }
        await f.cleanUp()
    }

    private static let server = #"""
#!/usr/bin/python3
import json, sys, os, time, threading, shutil
lock = threading.Lock()
def send(value):
    with lock:
        print(json.dumps(value), flush=True)
def worker(params):
    thread = params['threadId']
    asked = False
    with open('live.txt', 'a') as live:
        open('started', 'w').close()
        while True:
            live.write('x'); live.flush()
            if os.path.exists('ask') and not asked:
                asked = True
                send({'id': 77, 'method': 'item/commandExecution/requestApproval', 'params': {'threadId': thread, 'turnId': 'turn', 'command': 'test'}})
            if os.path.exists('fail'):
                send({'method':'turn/completed','params':{'threadId':thread,'turn':{'id':'turn','status':'failed','error':{'message':'Test failure'}}}})
                return
            if os.path.exists('finish'):
                reference = next(i['path'] for i in params['input'] if i['type'] == 'localImage')
                shutil.copyfile(reference, 'generated.png')
                send({'method':'item/completed','params':{'threadId':thread,'item':{'type':'imageGeneration','status':'completed','savedPath':os.path.abspath('generated.png')}}})
                send({'method':'turn/completed','params':{'threadId':thread,'turn':{'id':'turn','status':'completed'}}})
                return
            time.sleep(.02)
for line in sys.stdin:
    request = json.loads(line)
    method = request.get('method')
    params = request.get('params', {})
    result = {}
    if method == 'initialized': continue
    if method is None:
        if request.get('id') == 77: open('approved','w').close()
        continue
    if method == 'initialize': result = {'userAgent':'codex/test'}
    elif method == 'account/read': result = {'account':{'type':'chatgpt'}}
    elif method == 'modelProvider/capabilities/read': result = {'imageGeneration':True}
    elif method in ('thread/start','thread/resume'):
        result = {'thread':{'id': params.get('threadId', os.path.basename(os.getcwd()))}, 'model':'test'}
    elif method == 'turn/start':
        with open('prompt.txt','w') as f: f.write(params['input'][0]['text'])
        result = {'turn':{'id':'turn','status':'inProgress'}}
        threading.Thread(target=worker, args=(params,), daemon=True).start()
    elif method == 'turn/interrupt':
        send({'method':'turn/completed','params':{'threadId':params['threadId'],'turn':{'id':'turn','status':'interrupted'}}})
    send({'id':request['id'],'result':result})
"""#
}
