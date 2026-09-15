import Foundation
import Testing
@testable import PlexBarStudio

@Suite struct StudioTitleSortingTests {
    @Test(arguments: ["The General", "A Star Is Born", "An American in Paris", "Theatre of Blood"])
    func missingSortTitleUsesTheUnchangedTitle(title: String) {
        let record = record(title)
        #expect(record.sortTitle == title)
        #expect(record.title == title)
    }

    @Test func explicitSortTitleTakesPrecedence() {
        var record = record("The General")
        record.metadata["titleSort"] = .string("  General, The  ")
        #expect(record.sortTitle == "General, The")
        #expect(record.title == "The General")
        record.metadata["titleSort"] = .string("Zebra")
        #expect(record.sortTitle == "Zebra")
        record.metadata["titleSort"] = .string(" \n ")
        #expect(record.sortTitle == "The General")
    }

    @Test func galleryUsesNaturalOrderAndStableTiesWithoutStrippingUserNames() {
        func item(_ id: String, _ title: String, sortTitle: String? = nil) -> StudioGalleryItem {
            StudioGalleryItem(id: id, title: title, subtitle: "", category: .movies, ratio: 1, sortTitle: sortTitle)
        }
        var user = item("user", "The General")
        user.category = .users
        let items = [
            user,
            item("10", "The Chapter 10", sortTitle: "Chapter 10"),
            item("2", "The Chapter 2", sortTitle: "Chapter 2"),
            item("b", "The General", sortTitle: "General"),
            item("a", "The General", sortTitle: "General"),
            item("plain", "General", sortTitle: "General")
        ]
        #expect(items.sorted(by: StudioGalleryItem.orderedByTitle).map(\.id) == ["2", "10", "plain", "a", "b", "user"])
    }

    private func record(_ title: String) -> StudioCatalogRecord {
        StudioCatalogRecord(sources: [], addedAtSecondsAgo: 0, relatedIDs: [], extraIDs: [],
                            metadata: .object(["title": .string(title)]))
    }
}
