import Foundation
import PlexModels

/// The mock keeps PMS metadata verbatim so browsing and details use the same contract.
/// Source citations and sample-library relationships stay outside the PMS response.
public struct PlexMockMediaCatalog: Sendable {
    public struct Record: Sendable {
        public let item: PlexMediaItem
        public let metadataData: Data
        public let sources: [URL]
        public let addedAtSecondsAgo: Int
        public let relatedIDs: [String]
        public let extraIDs: [String]

        public func object(referenceDate: Date) -> [String: Any] {
            // Validated once when the catalog is loaded.
            var object = try! JSONSerialization.jsonObject(with: metadataData) as! [String: Any]
            object["addedAt"] = Int(referenceDate.timeIntervalSince1970) - addedAtSecondsAgo
            return object
        }
    }

    public let records: [Record]
    private let recordsByID: [String: Record]

    public init(data: Data) throws {
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CatalogError.invalid("Expected an array of catalog records")
        }
        var records: [Record] = []
        var recordsByID: [String: Record] = [:]
        for entry in entries {
            guard let metadata = entry["metadata"] as? [String: Any],
                  let sourceStrings = entry["sources"] as? [String], !sourceStrings.isEmpty,
                  let addedAtSecondsAgo = entry["addedAtSecondsAgo"] as? Int,
                  let relatedIDs = entry["relatedIDs"] as? [String],
                  let extraIDs = entry["extraIDs"] as? [String],
                  addedAtSecondsAgo >= 0 else {
                throw CatalogError.invalid("Each record needs metadata, sources, relationship arrays, and a nonnegative age")
            }
            let sources = try sourceStrings.map { source in
                guard let url = URL(string: source), url.scheme == "https", url.host != nil else {
                    throw CatalogError.invalid("Invalid source URL: \(source)")
                }
                return url
            }
            let metadataData = try JSONSerialization.data(withJSONObject: metadata)
            let item = try JSONDecoder().decode(PlexMediaItem.self, from: metadataData)
            guard !item.ratingKey.isEmpty, recordsByID[item.ratingKey] == nil,
                  item.type != nil, item.key != nil, metadata["title"] is String else {
                throw CatalogError.invalid("Missing identity, type, key, title, or duplicate ID: \(item.ratingKey)")
            }
            guard item.media.allSatisfy({ $0.parts.isEmpty }) else {
                throw CatalogError.invalid("The browse-only catalog must not contain playback parts")
            }
            let record = Record(
                item: item,
                metadataData: metadataData,
                sources: sources,
                addedAtSecondsAgo: addedAtSecondsAgo,
                relatedIDs: relatedIDs,
                extraIDs: extraIDs
            )
            records.append(record)
            recordsByID[item.ratingKey] = record
        }
        self.records = records
        self.recordsByID = recordsByID
        try validateRelationships()
    }

    public func record(for id: String) -> Record? {
        recordsByID[id]
    }

    public func children(of id: String) -> [Record] {
        records.filter { $0.item.parentRatingKey == id }
            .sorted { ($0.item.index ?? 0, $0.item.ratingKey) < ($1.item.index ?? 0, $1.item.ratingKey) }
    }

    public func leaves(of id: String) -> [Record] {
        children(of: id).flatMap { record in
            record.item.hasChildren ? leaves(of: record.item.ratingKey) : [record]
        }
    }

    private func validateRelationships() throws {
        for record in records {
            let item = record.item
            let references = [item.parentRatingKey, item.grandparentRatingKey].compactMap { $0 }
                + record.relatedIDs + record.extraIDs
            guard references.allSatisfy({ recordsByID[$0] != nil && $0 != item.ratingKey }) else {
                throw CatalogError.invalid("Unresolved or self-referencing relationship: \(item.ratingKey)")
            }
            var ancestors: Set<String> = [item.ratingKey]
            var parent = item.parentRatingKey
            while let parentID = parent {
                guard ancestors.insert(parentID).inserted else {
                    throw CatalogError.invalid("Hierarchy cycle: \(item.ratingKey)")
                }
                parent = recordsByID[parentID]?.item.parentRatingKey
            }
            if let parentID = item.parentRatingKey, let parent = recordsByID[parentID]?.item {
                let expectedParent: String? = switch item.type {
                case "season": "show"
                case "episode": "season"
                case "album": "artist"
                case "track": "album"
                default: nil
                }
                if let expectedParent, parent.type != expectedParent {
                    throw CatalogError.invalid("Incorrect parent type: \(item.ratingKey)")
                }
                if let grandparentID = item.grandparentRatingKey, parent.parentRatingKey != grandparentID {
                    throw CatalogError.invalid("Incorrect grandparent: \(item.ratingKey)")
                }
            }
        }
        // Check counts only after cycle validation, before traversing the hierarchy.
        for record in records where record.item.hasChildren {
            let item = record.item
            if let count = item.childCount, count != children(of: item.ratingKey).count {
                throw CatalogError.invalid("Incorrect child count: \(item.ratingKey)")
            }
            if let count = item.leafCount, count != leaves(of: item.ratingKey).count {
                throw CatalogError.invalid("Incorrect leaf count: \(item.ratingKey)")
            }
        }
    }

    public enum CatalogError: Error, LocalizedError, Sendable {
        case invalid(String)

        public var errorDescription: String? {
            switch self {
            case .invalid(let message): "Invalid mock catalog: \(message)"
            }
        }
    }
}
