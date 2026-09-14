import PlexMockData
import Foundation

struct StudioPack: Sendable {
    var records: [StudioCatalogRecord]
    var payload: StudioJSON

    var assets: [StudioAsset] {
        (payload["artwork"]?.array ?? []).compactMap { value in
            guard let path = value["path"]?.string, let resource = value["resource"]?.string else { return nil }
            return StudioAsset(path: path, resource: resource)
        }
    }

    func artwork(for record: StudioCatalogRecord) -> [StudioAsset] {
        let paths = Set(["thumb", "art", "parentThumb", "grandparentThumb"].compactMap { record.metadata[$0]?.string })
        return assets.filter { paths.contains($0.path) }
    }

    func validate() -> [StudioValidationIssue] {
        var issues: [StudioValidationIssue] = []
        func issue(_ context: String, _ message: String) { issues.append(.init(context: context, message: message)) }
        do {
            let contract = try JSONDecoder().decode(PlexMockServerPayload.self, from: payload.encoded())
            try contract.validateProfiles()
            _ = try PlexMockMediaCatalog(data: JSONEncoder().encode(records))
        } catch { issue("Plex contract", error.localizedDescription) }
        var byID: [String: StudioCatalogRecord] = [:]
        for record in records {
            if record.id.isEmpty || byID[record.id] != nil { issue(record.title, "Missing or duplicate rating key.") }
            else { byID[record.id] = record }
            if record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issue(record.id, "A title is required.") }
            let childSuffix = ["show", "season", "artist", "album"].contains(record.type) ? "/children" : ""
            if record.metadata["key"]?.string != "/library/metadata/\(record.id)\(childSuffix)" { issue(record.title, "Metadata key must match the rating key and media type.") }
            if !["movie", "show", "season", "episode", "artist", "album", "track", "clip"].contains(record.type) {
                issue(record.title, "Unsupported catalog media type: \(record.type).")
            }
            if record.addedAtSecondsAgo < 0 { issue(record.title, "Date-added age cannot be negative.") }
            if record.sources.isEmpty || record.sources.contains(where: { URL(string: $0)?.scheme != "https" || URL(string: $0)?.host == nil }) {
                issue(record.title, "At least one valid HTTPS source is required.")
            }
            for media in record.metadata["Media"]?.array ?? [] where !(media["Part"]?.array ?? []).isEmpty {
                issue(record.title, "Browse-only mock records cannot contain playback parts.")
            }
        }
        let children = Dictionary(grouping: records.filter { $0.parentID != nil }, by: { $0.parentID! })
        let expectedParents = ["season": "show", "episode": "season", "album": "artist", "track": "album"]
        for record in records {
            let refs = [record.parentID, record.metadata["grandparentRatingKey"]?.string].compactMap { $0 } + record.relatedIDs + record.extraIDs
            if refs.contains(where: { byID[$0] == nil || $0 == record.id }) { issue(record.title, "A relationship is unresolved or refers to itself.") }
            if let expected = expectedParents[record.type], record.parentID.flatMap({ byID[$0]?.type }) != expected {
                issue(record.title, "A \(record.type) must have a \(expected) parent.")
            }
            if let grandparent = record.metadata["grandparentRatingKey"]?.string,
               record.parentID.flatMap({ byID[$0]?.parentID }) != grandparent {
                issue(record.title, "Grandparent does not match the parent hierarchy.")
            }
            for prefix in ["parent", "grandparent"] {
                if let ancestorID = record.metadata[prefix + "RatingKey"]?.string,
                   let ancestor = byID[ancestorID],
                   let inheritedTitle = record.metadata[prefix + "Title"],
                   inheritedTitle != ancestor.metadata["title"] {
                    issue(record.title, "\(prefix)Title does not match \(ancestor.title).")
                }
            }
            var ancestors: Set<String> = [record.id]
            var parent = record.parentID
            var cycle = false
            while let id = parent {
                if !ancestors.insert(id).inserted { cycle = true; break }
                parent = byID[id]?.parentID
            }
            if cycle { issue(record.title, "The hierarchy contains a cycle.") }
            if let count = record.metadata["childCount"]?.integer, count != (children[record.id] ?? []).count {
                issue(record.title, "Child count does not match the catalog.")
            }
            if let count = record.metadata["leafCount"]?.integer {
                var visited: Set<String> = [record.id]
                var pending = children[record.id] ?? []
                var leaves = 0
                while let child = pending.popLast() {
                    guard visited.insert(child.id).inserted else { continue }
                    if ["show", "season", "artist", "album"].contains(child.type) { pending += children[child.id] ?? [] }
                    else { leaves += 1 }
                }
                if count != leaves { issue(record.title, "Leaf count does not match the catalog.") }
            }
            if record.type == "album", let duration = record.metadata["duration"]?.integer,
               duration != (children[record.id] ?? []).reduce(0, { $0 + ($1.metadata["duration"]?.integer ?? 0) }) {
                issue(record.title, "Album duration does not equal its chapter durations.")
            }
        }
        let assetPaths = Set(assets.map(\.path))
        if assetPaths.count != assets.count { issue("Artwork", "Artwork paths must be unique.") }
        for record in records {
            for field in ["thumb", "art", "parentThumb", "grandparentThumb"] {
                if let path = record.metadata[field]?.string, !assetPaths.contains(path) { issue(record.title, "\(field) does not resolve to registered artwork.") }
            }
        }
        for group in ["activeSessions", "historyEvents"] {
            guard let entries = payload[group]?.array else { issue(group, "Expected an array."); continue }
            for entry in entries {
                guard let mediaID = entry["mediaID"]?.string, let record = byID[mediaID] else { issue(group, "Media reference is missing."); continue }
                if entry["mediaType"]?.string != record.type { issue(group, "Media type does not match \(record.title).") }
            }
        }
        for library in payload["libraries"]?.array ?? [] {
            for entry in library["entries"]?.array ?? [] {
                if entry["mediaID"]?.string.flatMap({ byID[$0]?.type }) != library["type"]?.string {
                    issue(library["title"]?.string ?? "Library", "Library root must resolve to its declared media type.")
                }
            }
        }
        return issues
    }

}
