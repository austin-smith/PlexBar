import Foundation
import PlexModels
import Testing
@testable import PlexBar

struct PlexPlayerContentMetadataTests {
    @Test func episodeUsesExistingHeadingAndSeriesTitle() throws {
        let metadata = try presentation(#"{"ratingKey":"1","type":"episode","title":"The Past Will Eat You Alive","grandparentTitle":"Survivor","parentIndex":35,"index":5}"#)
        #expect(metadata.title == "Survivor")
        #expect(metadata.details == ["S35 • E5 - The Past Will Eat You Alive"])
    }

    @Test func movieUsesTitleAndExistingYearSubtitle() throws {
        let metadata = try presentation(#"{"ratingKey":"2","type":"movie","title":"American Fiction","year":2023}"#)
        #expect(metadata.title == "American Fiction")
        #expect(metadata.details == ["2023"])
    }

    @Test func audioPreservesExistingAuthorAndBookPresentation() throws {
        let metadata = try presentation(#"{"ratingKey":"3","type":"track","title":"Chapter 3","grandparentTitle":"Anthony Bourdain","parentTitle":"Kitchen Confidential","Media":[{"audioCodec":"aac","Part":[{"id":"50"}]}]}"#)
        #expect(metadata.title == "Chapter 3")
        #expect(metadata.details == ["Anthony Bourdain", "Kitchen Confidential"])
    }

    @Test func absentEpisodeHierarchyDoesNotRepeatTitleOrInventNumbers() throws {
        let metadata = try presentation(#"{"ratingKey":"4","type":"episode","title":"Special"}"#)
        #expect(metadata.title == nil)
        #expect(metadata.details == ["Special"])
    }

    @Test func videoWithoutMetadataStillShowsItsTitle() throws {
        let metadata = try presentation(#"{"ratingKey":"5","title":"Home Video"}"#)
        #expect(metadata.title == "Home Video")
        #expect(metadata.details.isEmpty)
    }

    private func presentation(_ json: String) throws -> PlexPlayerContentMetadata {
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
        return PlexPlayerContentMetadata(item: item, source: .init(mediaIndex: 0, partIndex: 0))
    }
}
