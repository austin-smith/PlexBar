import Foundation
import Testing
@testable import PlexBarStudio

@Suite struct StudioMovieArtworkTests {
    @Test func existingMovieFoldersRemainStableWhenTitlesChange() throws {
        let pack = try StudioFiles.loadPack(at: StudioFiles.repositoryContentURL)
        for record in pack.records where record.type == "movie" && !pack.artwork(for: record).isEmpty {
            for asset in pack.artwork(for: record) {
                #expect(try StudioMovieArtwork.path(for: record, role: asset.role, in: pack) == asset.path)
            }
        }
        var charade = try #require(pack.records.first { $0.title == "Charade" })
        charade.metadata["title"] = .string("A changed display title")
        #expect(try StudioMovieArtwork.path(for: charade, role: .poster, in: pack) == "/mock/art/movies/charade/poster.png")
        #expect(try StudioMovieArtwork.path(for: charade, role: .backdrop, in: pack) == "/mock/art/movies/charade/backdrop.jpg")
    }

    @Test func newMovieFoldersHandlePunctuationAndRejectConflictingDestinations() throws {
        let pack = try StudioFiles.loadPack(at: StudioFiles.repositoryContentURL)
        var record = StudioCatalogRecord(
            sources: [], addedAtSecondsAgo: 0, relatedIDs: [], extraIDs: [],
            metadata: .object([
                "ratingKey": .string("new-movie-artwork-test"),
                "type": .string("movie"),
                "title": .string("Studio Test Movie"),
            ])
        )
        #expect(pack.artwork(for: record).isEmpty)
        #expect(try StudioMovieArtwork.path(for: record, role: .poster, in: pack) == "/mock/art/movies/studio-test-movie/poster.png")
        record.metadata["title"] = .string("Amélie's / Test: Movie!")
        #expect(try StudioMovieArtwork.path(for: record, role: .backdrop, in: pack) == "/mock/art/movies/amelies-test-movie/backdrop.jpg")
        record.metadata["title"] = .string("Charade")
        #expect(throws: (any Error).self) { try StudioMovieArtwork.path(for: record, role: .poster, in: pack) }
        record.metadata["title"] = .string("../")
        #expect(throws: (any Error).self) { try StudioMovieArtwork.path(for: record, role: .poster, in: pack) }
    }

    @Test @MainActor func generatingAndAcceptingNewMovieArtworkUseTheSameTitleFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "studio-movie-path-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = root.appending(path: "MockServer")
        try FileManager.default.copyItem(at: StudioFiles.repositoryContentURL, to: content)
        let history = try StudioFiles.historyURL(in: content)
        if FileManager.default.fileExists(atPath: history.path) { try FileManager.default.removeItem(at: history) }
        // The deliberately absent executable prevents this path test from invoking real generation.
        let store = StudioStore(contentURL: content, codexExecutable: root.appending(path: "absent-codex").path)
        await store.loadContent()
        let item = try #require(store.items.first { $0.title == "A Star Is Born" })
        let recordID = try #require(item.recordID)
        let reference = content.appending(path: "art/movies/charade/masters/poster.png")
        let id = try #require(store.generate(item: item, role: .poster, instructions: "", referencePath: "", referenceFileURL: reference))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while store.hasActiveGenerations && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        if store.hasActiveGenerations { store.cancelGeneration(id) }
        try #require(!store.hasActiveGenerations)
        let jobIndex = try #require(store.manifest.jobs.firstIndex { $0.id == id })
        let path = "/mock/art/movies/a-star-is-born/poster.png"
        #expect(store.manifest.jobs[jobIndex].artwork?.assetPath == path)

        let data = try Data(contentsOf: reference)
        var candidate = StudioCandidate(id: id, title: item.title, recordID: item.recordID,
            assetPath: "/mock/art/studio/\(recordID)/poster.png", role: .poster,
            file: "candidates/\(id.uuidString).png", prompt: "Test destination", model: "test", jobID: id,
            referenceHashes: [], outputHash: StudioFiles.hash(data), createdAt: Date(), decision: .pending)
        store.manifest.jobs[jobIndex].status = .review
        store.manifest.candidates = [candidate]
        try StudioFiles.saveHistory(store.manifest, at: history, files: [candidate.file: data])
        let before = try StudioFiles.fingerprints(at: content)
        #expect(!store.decide(candidate, accept: true))
        #expect(try StudioFiles.fingerprints(at: content) == before)

        candidate.assetPath = path
        store.manifest.candidates = [candidate]
        store.errorMessage = nil
        #expect(store.decide(candidate, accept: true))
        let reopened = try StudioFiles.loadPack(at: content)
        #expect(reopened.records.first { $0.id == item.recordID }?.metadata["thumb"]?.string == path)
        #expect(reopened.assets.first { $0.path == path }?.resource == "art/movies/a-star-is-born/poster.png")
        #expect(try Data(contentsOf: content.appending(path: "art/movies/a-star-is-born/poster.png")) == StudioFiles.exportImage(data, role: .poster))
        #expect(!FileManager.default.fileExists(atPath: content.appending(path: "art/studio/\(recordID)/poster.png").path))
    }
}
