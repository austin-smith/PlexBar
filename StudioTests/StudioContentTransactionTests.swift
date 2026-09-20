import Foundation
import Testing
@testable import PlexBarStudio

@Suite struct StudioContentTransactionTests {
    @Test func interruptedCommitRestoresOriginalsWithoutTouchingJobFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "studio-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appending(path: ".studio/content-transaction")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        let original = Data("original".utf8)
        let replacement = Data("replacement".utf8)
        try original.write(to: journal.appending(path: "0.backup"))
        try replacement.write(to: root.appending(path: "media-catalog.json"))
        try replacement.write(to: root.appending(path: "new-artwork.png"))
        let entries: [[String: Any]] = [
            ["path": "media-catalog.json", "before": StudioFiles.hash(original), "after": StudioFiles.hash(replacement), "backup": "0.backup"],
            ["path": "new-artwork.png", "after": StudioFiles.hash(replacement), "backup": "1.backup"]
        ]
        try JSONSerialization.data(withJSONObject: entries).write(to: journal.appending(path: "entries.json"))
        let active = root.appending(path: ".studio/live-job.txt")
        try Data("live job".utf8).write(to: active)
        try StudioContentTransaction.recover(at: root)
        #expect(try Data(contentsOf: root.appending(path: "media-catalog.json")) == original)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "new-artwork.png").path))
        #expect(try String(contentsOf: active, encoding: .utf8) == "live job")
        #expect(!FileManager.default.fileExists(atPath: journal.path))
    }

    @Test func interruptedCommitDoesNotOverwriteExternalEdits() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "studio-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appending(path: ".studio/content-transaction")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        let target = root.appending(path: "media-catalog.json")
        try Data("external edit".utf8).write(to: target)
        let entries = [["path": "media-catalog.json", "before": "old", "after": "new", "backup": "0.backup"]]
        try JSONSerialization.data(withJSONObject: entries).write(to: journal.appending(path: "entries.json"))
        #expect(throws: (any Error).self) { try StudioContentTransaction.recover(at: root) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "external edit")
        #expect(FileManager.default.fileExists(atPath: journal.path))
    }
}
