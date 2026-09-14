import Foundation
import PlexMockData
import Testing
@testable import PlexBarStudio

@Suite struct StudioMetadataEditingTests {
    struct RenameCase: Sendable {
        let recordID: String
        let childID: String
        let grandchildID: String?
    }

    @Test(arguments: [
        RenameCase(recordID: "2103", childID: "2301", grandchildID: "2201"), // Show
        RenameCase(recordID: "2301", childID: "2201", grandchildID: nil), // Season
        RenameCase(recordID: "3001", childID: "3101", grandchildID: "32101"), // Author
        RenameCase(recordID: "3101", childID: "32101", grandchildID: nil), // Audiobook
    ])
    @MainActor func renamingUpdatesPersistedDescendantTitles(scenario: RenameCase) async throws {
        let content = try copyContent()
        defer { try? FileManager.default.removeItem(at: content) }
        let store = StudioStore(contentURL: content)
        await store.loadContent()
        let original = try #require(store.pack)
        let record = try #require(original.records.first { $0.id == scenario.recordID })
        var metadata = record.metadata
        let renamedTitle = "Renamed \(record.title)"
        metadata["title"] = .string(renamedTitle)

        try store.applyMetadataJSON(metadata.prettyPrinted, recordID: record.id)
        await store.loadContent()
        let reopened = try #require(store.pack)
        let catalog = try PlexMockMediaCatalog(data: Data(contentsOf: content.appending(path: "media-catalog.json")))
        #expect(catalog.record(for: record.id)?.item.title == renamedTitle)
        #expect(catalog.record(for: scenario.childID)?.item.parentTitle == renamedTitle)
        if let grandchildID = scenario.grandchildID {
            #expect(catalog.record(for: grandchildID)?.item.grandparentTitle == renamedTitle)
        }
        #expect(reopened.validate().isEmpty)
        #expect(reopened.payload == original.payload)
        for unchanged in original.records where unchanged.id != record.id
            && unchanged.parentID != record.id
            && unchanged.metadata["grandparentRatingKey"]?.string != record.id {
            #expect(reopened.records.first { $0.id == unchanged.id } == unchanged)
        }
        // Descendant titles, identities, sources, and artwork must survive the rename.
        for descendant in reopened.records where descendant.id != record.id {
            let before = try #require(original.records.first { $0.id == descendant.id })
            #expect(descendant.title == before.title)
            #expect(descendant.parentID == before.parentID)
            #expect(descendant.sources == before.sources)
            #expect(reopened.artwork(for: descendant) == original.artwork(for: before))
        }
    }

    @Test(arguments: ["parentTitle", "grandparentTitle"])
    @MainActor func conflictingInheritedTitlesAreRejected(field: String) async throws {
        let content = try copyContent()
        defer { try? FileManager.default.removeItem(at: content) }
        let store = StudioStore(contentURL: content)
        await store.loadContent()
        let original = try #require(store.pack)
        let index = try #require(original.records.firstIndex { $0.id == "2201" })
        var metadata = original.records[index].metadata
        metadata[field] = .string("Wrong ancestor")
        var invalid = original
        invalid.records[index].metadata = metadata
        #expect(invalid.validate().contains { $0.message.contains(field) })
        let before = try StudioFiles.fingerprints(at: content)

        #expect(throws: (any Error).self) {
            try store.applyMetadataJSON(metadata.prettyPrinted, recordID: "2201")
        }
        #expect(store.pack?.records == original.records)
        #expect(try StudioFiles.fingerprints(at: content) == before)
    }

    @Test @MainActor func outsideConflictDoesNotPartiallyRenameTheHierarchy() async throws {
        let content = try copyContent()
        defer { try? FileManager.default.removeItem(at: content) }
        let store = StudioStore(contentURL: content)
        await store.loadContent()
        let original = try #require(store.pack)
        let show = try #require(original.records.first { $0.id == "2103" })
        var metadata = show.metadata
        metadata["title"] = .string("Conflicting rename")
        try Data("external edit".utf8).write(to: content.appending(path: "outside.txt"))
        let before = try StudioFiles.fingerprints(at: content)

        #expect(throws: (any Error).self) {
            try store.applyMetadataJSON(metadata.prettyPrinted, recordID: show.id)
        }
        #expect(store.pack?.records == original.records)
        #expect(try StudioFiles.fingerprints(at: content) == before)
    }

    private func copyContent() throws -> URL {
        let content = FileManager.default.temporaryDirectory.appending(path: "studio-metadata-tests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: StudioFiles.repositoryContentURL, to: content)
        let history = try StudioFiles.historyURL(in: content)
        if FileManager.default.fileExists(atPath: history.path) { try FileManager.default.removeItem(at: history) }
        return content
    }
}
