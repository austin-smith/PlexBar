import Foundation
import PlexMockData
import Testing

@Suite struct PlexMockMediaCatalogTests {
    @Test func preservesPMSFieldsAndAppliesRelativeDates() throws {
        let data = try catalogData([
            entry(id: "movie", metadata: ["customField": ["value": "preserved"]]),
        ])
        let catalog = try PlexMockMediaCatalog(data: data)
        let record = try #require(catalog.record(for: "movie"))
        let object = record.object(referenceDate: Date(timeIntervalSince1970: 1_000))

        #expect(record.item.title == "Example")
        #expect(record.sources.map(\.absoluteString) == ["https://example.com/source"])
        #expect(object["customField"] as? [String: String] == ["value": "preserved"])
        #expect(object["addedAt"] as? Int == 900)
    }

    @Test func rejectsDuplicateIDsAndPlaybackParts() throws {
        let duplicate = try catalogData([entry(id: "movie"), entry(id: "movie")])
        #expect(throws: PlexMockMediaCatalog.CatalogError.self) {
            try PlexMockMediaCatalog(data: duplicate)
        }

        let playable = try catalogData([
            entry(id: "movie", metadata: ["Media": [["Part": [["key": "/playback"]]]]]),
        ])
        #expect(throws: PlexMockMediaCatalog.CatalogError.self) {
            try PlexMockMediaCatalog(data: playable)
        }
    }

    @Test func rejectsCyclesBeforeTraversingChildCounts() throws {
        let cyclic = try catalogData([
            entry(id: "a", metadata: ["type": "show", "parentRatingKey": "b", "childCount": 1]),
            entry(id: "b", metadata: ["type": "show", "parentRatingKey": "a", "childCount": 1]),
        ])
        #expect(throws: PlexMockMediaCatalog.CatalogError.self) {
            try PlexMockMediaCatalog(data: cyclic)
        }
    }

    private func entry(id: String, metadata: [String: Any] = [:]) -> [String: Any] {
        [
            "metadata": ["ratingKey": id, "key": "/library/metadata/\(id)", "type": "movie", "title": "Example"]
                .merging(metadata) { _, replacement in replacement },
            "sources": ["https://example.com/source"],
            "addedAtSecondsAgo": 100,
            "relatedIDs": [String](),
            "extraIDs": [String](),
        ]
    }

    private func catalogData(_ entries: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: entries)
    }
}
