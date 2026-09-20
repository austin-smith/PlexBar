import Foundation

struct StudioTitleDraft: Codable, Sendable {
    var notes: String
    var records: [Record]

    struct Record: Codable, Sendable {
        var localID: String
        var parentLocalID: String?
        var type: String
        var title: String
        var year: Int?
        var durationMilliseconds: Int?
        var summary: String
        var index: Int?
        var sources: [String]
        var genres: [String]
        var studio: String?
        var releaseDate: String?
    }

    /// Allocates identities once, then derives the PMS hierarchy from explicit relationships.
    func compile(into original: StudioPack) throws -> (pack: StudioPack, titleID: String) {
        guard !records.isEmpty else { throw StudioError.invalid("The metadata draft contains no records.") }
        let localIDs = records.map(\.localID)
        guard Set(localIDs).count == records.count, !localIDs.contains("") else { throw StudioError.invalid("Draft identities must be present and unique.") }
        let titleRecords = records.filter { ["movie", "show", "album"].contains($0.type) }
        guard titleRecords.count == 1, let title = titleRecords.first else { throw StudioError.invalid("Create one movie, show, or audiobook at a time.") }
        let draftRoots = records.filter { $0.parentLocalID == nil }
        guard draftRoots.count == 1, let root = draftRoots.first,
              root.type == (title.type == "album" ? "artist" : title.type) else {
            throw StudioError.invalid("The draft must have exactly one connected title hierarchy.")
        }
        for record in records {
            if let duration = record.durationMilliseconds, duration < 0 { throw StudioError.invalid("Durations cannot be negative.") }
        }
        var nextID = max(100_000, original.records.compactMap { Int($0.id) }.max() ?? 0)
        guard nextID < Int.max - records.count else { throw StudioError.invalid("Catalog identifiers exceed the supported range.") }
        var ids: [String: String] = [:]
        for record in records { nextID += 1; ids[record.localID] = String(nextID) }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.localID, $0) })
        let libraryType = title.type == "album" ? "artist" : title.type
        guard let library = original.payload["libraries"]?.array?.first(where: { $0["type"]?.string == libraryType }),
              let libraryID = library["id"]?.string, let libraryTitle = library["title"]?.string else {
            throw StudioError.invalid("The mock pack needs a \(libraryType) library before adding this title.")
        }
        var compiled: [StudioCatalogRecord] = []
        for record in records {
            guard let id = ids[record.localID] else { throw StudioError.invalid("Missing draft identity.") }
            var metadata: StudioJSON = .object([
                "ratingKey": .string(id), "key": .string("/library/metadata/\(id)" + (["show", "season", "artist", "album"].contains(record.type) ? "/children" : "")),
                "type": .string(record.type), "title": .string(record.title),
                "librarySectionID": .string(libraryID), "librarySectionTitle": .string(libraryTitle),
                "summary": .string(record.summary), "Genre": .array(record.genres.map { .object(["tag": .string($0)]) })
            ])
            metadata["year"] = record.year.map(StudioJSON.integer)
            metadata["duration"] = record.durationMilliseconds.map(StudioJSON.integer)
            metadata["index"] = record.index.map(StudioJSON.integer)
            metadata["studio"] = record.studio.map(StudioJSON.string)
            metadata["originallyAvailableAt"] = record.releaseDate.map(StudioJSON.string)
            if let parentLocalID = record.parentLocalID {
                guard let parent = byID[parentLocalID], let parentID = ids[parentLocalID] else { throw StudioError.invalid("Unresolved parent for \(record.title).") }
                metadata["parentRatingKey"] = .string(parentID)
                metadata["parentTitle"] = .string(parent.title)
                metadata["parentIndex"] = parent.index.map(StudioJSON.integer)
                if let grandparentLocalID = parent.parentLocalID {
                    guard let grandparent = byID[grandparentLocalID], let grandparentID = ids[grandparentLocalID] else { throw StudioError.invalid("Unresolved grandparent.") }
                    metadata["grandparentRatingKey"] = .string(grandparentID)
                    metadata["grandparentTitle"] = .string(grandparent.title)
                }
            }
            compiled.append(.init(sources: record.sources, addedAtSecondsAgo: 3600, relatedIDs: [], extraIDs: [], metadata: metadata))
        }
        // Validate the graph before any recursive traversal or derived counts.
        var pack = original
        pack.records += compiled
        let problems = pack.validate()
        guard problems.isEmpty else { throw StudioError.invalid(problems.map { "\($0.context): \($0.message)" }.joined(separator: "\n")) }
        for index in compiled.indices where ["show", "season", "artist", "album"].contains(compiled[index].type) {
            let id = compiled[index].id
            let children = compiled.filter { $0.parentID == id }
            var pending = children
            var leaves: [StudioCatalogRecord] = []
            while let child = pending.popLast() {
                if ["season", "album"].contains(child.type) { pending += compiled.filter { $0.parentID == child.id } }
                else { leaves.append(child) }
            }
            compiled[index].metadata["childCount"] = .integer(children.count)
            compiled[index].metadata["leafCount"] = .integer(leaves.count)
            if compiled[index].type == "album", children.allSatisfy({ $0.metadata["duration"]?.integer != nil }) {
                compiled[index].metadata["duration"] = .integer(children.reduce(0) { $0 + ($1.metadata["duration"]?.integer ?? 0) })
            }
        }
        pack.records = original.records + compiled
        var libraries = pack.payload["libraries"]?.array ?? []
        guard let libraryIndex = libraries.firstIndex(where: { $0["id"]?.string == libraryID }) else { throw StudioError.invalid("Missing destination library.") }
        let roots = compiled.filter { $0.parentID == nil }
        libraries[libraryIndex]["entries"] = .array((libraries[libraryIndex]["entries"]?.array ?? []) + roots.map { .object(["mediaID": .string($0.id)]) })
        pack.payload["libraries"] = .array(libraries)
        guard let titleID = ids[title.localID] else { throw StudioError.invalid("Missing title identity.") }
        let finalIssues = pack.validate()
        guard finalIssues.isEmpty else { throw StudioError.invalid(finalIssues.map(\.message).joined(separator: "\n")) }
        return (pack, titleID)
    }
}
