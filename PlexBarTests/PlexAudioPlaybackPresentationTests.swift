import PlexModels
import Foundation
import Testing
@testable import PlexBar

struct PlexAudioPlaybackPresentationTests {
    @Test func selectedAudioOnlySourceUsesTrackHierarchyAndCoverArtwork() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "track-9",
          "title": "Chapter 3",
          "type": "track",
          "grandparentTitle": "Anthony Bourdain",
          "parentTitle": "Kitchen Confidential",
          "thumb": "/tracks/9/thumb",
          "parentThumb": "/albums/4/thumb",
          "grandparentThumb": "/artists/2/thumb",
          "art": "/artists/2/art",
          "Media": [{
            "audioCodec": "aac",
            "Part": [{"id": "50"}]
          }]
        }
        """#)

        let presentation = try #require(PlexAudioPlaybackPresentation(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
        ))

        #expect(presentation.title == "Chapter 3")
        #expect(presentation.metadataLines == [
            "Anthony Bourdain",
            "Kitchen Confidential",
        ])
        #expect(presentation.artworkPaths == [
            "/albums/4/thumb",
            "/artists/2/thumb",
            "/tracks/9/thumb",
            "/artists/2/art",
        ])
    }

    @Test func selectedSourceFactsDetermineAudioPresentationWithoutTypeGuessing() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "mixed-1",
          "title": "Selected Source",
          "type": "track",
          "Media": [
            {"videoCodec": "h264", "audioCodec": "aac", "Part": [{"id": "1"}]},
            {"audioCodec": "flac", "Part": [{"id": "2"}]}
          ]
        }
        """#)

        #expect(PlexAudioPlaybackPresentation(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
        ) == nil)
        #expect(PlexAudioPlaybackPresentation(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 1, partIndex: 0)
        ) != nil)
    }

    @Test func absentOrIncompleteSelectedSourceFactsRemainVideoPresentation() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "unknown-1",
          "title": "Unknown Source",
          "type": "track",
          "Media": [{"Part": [{"id": "1"}]}]
        }
        """#)

        #expect(PlexAudioPlaybackPresentation(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
        ) == nil)
        #expect(PlexAudioPlaybackPresentation(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 9, partIndex: 0)
        ) == nil)
    }

    @Test func repeatedHierarchyLabelsAreNotRenderedTwice() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "book-1",
          "title": "The Left Hand of Darkness",
          "type": "track",
          "grandparentTitle": "Ursula K. Le Guin",
          "parentTitle": "The Left Hand of Darkness",
          "Media": [{"audioCodec": "aac", "Part": [{"id": "1"}]}]
        }
        """#)

        let presentation = try #require(PlexAudioPlaybackPresentation(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
        ))

        #expect(presentation.metadataLines == ["Ursula K. Le Guin"])
    }

    private func decodeItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }
}
