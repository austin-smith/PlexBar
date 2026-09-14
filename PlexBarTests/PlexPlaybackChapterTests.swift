import PlexModels
import Foundation
import Testing
@testable import PlexBar

struct PlexPlaybackChapterTests {
    @Test func metadataDecodesPlexChapterTimingAndArtwork() throws {
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: Data(#"""
        {
          "ratingKey": "42",
          "title": "Episode",
          "duration": 120000,
          "Chapter": [{
            "id": 81,
            "index": "2",
            "startTimeOffset": "30000",
            "endTimeOffset": 90000,
            "title": "The Chase",
            "thumb": "/library/media/99/chapterImages/2"
          }]
        }
        """#.utf8))

        #expect(item.chapters.count == 1)
        #expect(item.chapters.first?.id == "81")
        #expect(item.chapters.first?.index == 2)
        #expect(item.chapters.first?.startTimeOffset == 30_000)
        #expect(item.chapters.first?.endTimeOffset == 90_000)
        #expect(item.chapters.first?.title == "The Chase")
        #expect(item.chapters.first?.thumb == "/library/media/99/chapterImages/2")
    }

    @Test func playbackChaptersAreSortedNamedAndClampedToMediaDuration() throws {
        let chapters = try decodeChapters(#"""
        [
          {"id": 7, "index": 3, "startTimeOffset": 90000, "endTimeOffset": 140000},
          {"id": 7, "index": 1, "startTimeOffset": 0, "endTimeOffset": 30000},
          {
            "id": 7,
            "index": 2,
            "startTimeOffset": 30000,
            "endTimeOffset": 90000,
            "title": "  Arrival  ",
            "thumb": " /library/media/99/chapterImages/2 "
          }
        ]
        """#)

        let result = PlexPlaybackChapter.chapters(
            from: chapters,
            mediaDurationMilliseconds: 120_000
        )

        #expect(result.map(\.title) == ["Chapter 1", "Arrival", "Chapter 3"])
        #expect(result.map(\.startTime) == [0, 30, 90])
        #expect(result.map(\.duration) == [30, 60, 30])
        #expect(result.map(\.thumbnailPath) == [
            nil,
            "/library/media/99/chapterImages/2",
            nil
        ])
        #expect(Set(result.map(\.id)).count == 3)
    }

    @Test func playbackChaptersRejectInvalidAndOutOfBoundsRanges() throws {
        let chapters = try decodeChapters(#"""
        [
          {"index": 1, "startTimeOffset": -1, "endTimeOffset": 10000},
          {"index": 2, "startTimeOffset": 20000, "endTimeOffset": 20000},
          {"index": 3, "startTimeOffset": 120000, "endTimeOffset": 140000},
          {"index": 4, "startTimeOffset": 10000},
          {"index": 5, "startTimeOffset": 10000, "endTimeOffset": 20000}
        ]
        """#)

        let result = PlexPlaybackChapter.chapters(
            from: chapters,
            mediaDurationMilliseconds: 120_000
        )

        #expect(result.count == 1)
        #expect(result.first?.title == "Chapter 5")
        #expect(result.first?.startTime == 10)
        #expect(result.first?.duration == 10)
    }

    private func decodeChapters(_ json: String) throws -> [PlexMediaChapter] {
        try JSONDecoder().decode([PlexMediaChapter].self, from: Data(json.utf8))
    }
}
