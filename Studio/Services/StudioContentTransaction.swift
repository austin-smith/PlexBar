import Foundation

/// The store calls writes serially on the main actor. A durable undo journal also
/// protects catalog/decision consistency if Studio exits between file writes.
/// Generation workspaces are never copied, renamed, or replaced.
enum StudioContentTransaction {
    private struct Entry: Codable {
        let path: String
        let before: String?
        let after: String
        let backup: String
    }

    static func write(_ files: [String: Data], at root: URL) throws {
        try recover(at: root)
        let journal = try StudioFiles.resolved(".studio/content-transaction", in: root)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        var entries: [Entry] = []
        do {
            for (index, path) in files.keys.sorted().enumerated() {
                let target = try StudioFiles.resolved(path, in: root)
                let original = FileManager.default.fileExists(atPath: target.path) ? try Data(contentsOf: target) : nil
                let backup = "\(index).backup"
                try original?.write(to: journal.appending(path: backup), options: .atomic)
                entries.append(Entry(path: path, before: original.map(StudioFiles.hash),
                                     after: StudioFiles.hash(files[path]!), backup: backup))
            }
            // No content is modified until the complete undo journal is on disk.
            try JSONEncoder().encode(entries).write(to: journal.appending(path: "entries.json"), options: .atomic)
            for entry in entries {
                let target = try StudioFiles.resolved(entry.path, in: root)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try files[entry.path]!.write(to: target, options: .atomic)
            }
            try Data().write(to: journal.appending(path: "committed"), options: .atomic)
        } catch {
            do { try recover(at: root) }
            catch { throw StudioError.invalid("The save was interrupted and could not be restored: \(error.localizedDescription)") }
            throw error
        }
        // A committed journal is safe to clean up at the next load if removal fails.
        try? FileManager.default.removeItem(at: journal)
    }

    static func recover(at root: URL) throws {
        let journal = try StudioFiles.resolved(".studio/content-transaction", in: root)
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        let entriesURL = journal.appending(path: "entries.json")
        if !FileManager.default.fileExists(atPath: journal.appending(path: "committed").path),
           FileManager.default.fileExists(atPath: entriesURL.path) {
            let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: entriesURL))
            // Check all paths before restoring anything; never overwrite an outside edit.
            for entry in entries {
                let target = try StudioFiles.resolved(entry.path, in: root)
                let current = FileManager.default.fileExists(atPath: target.path) ? StudioFiles.hash(try Data(contentsOf: target)) : nil
                guard current == entry.before || current == entry.after else {
                    throw StudioError.invalid("Cannot restore the interrupted save because \(entry.path) changed outside Studio.")
                }
                if let before = entry.before {
                    let backup = try StudioFiles.resolved(entry.backup, in: journal)
                    guard StudioFiles.hash(try Data(contentsOf: backup)) == before else {
                        throw StudioError.invalid("The interrupted save’s backup for \(entry.path) is damaged.")
                    }
                }
            }
            for entry in entries.reversed() {
                let target = try StudioFiles.resolved(entry.path, in: root)
                if entry.before != nil {
                    try Data(contentsOf: StudioFiles.resolved(entry.backup, in: journal)).write(to: target, options: .atomic)
                } else if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
            }
        }
        try FileManager.default.removeItem(at: journal)
    }
}
