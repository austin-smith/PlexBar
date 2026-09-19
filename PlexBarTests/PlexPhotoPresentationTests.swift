@testable import PlexClientKit
import PlexModels
import CoreGraphics
import Foundation
import Testing
@testable import PlexBar

@Suite
struct PlexPhotoPresentationTests {
    @Test func usesTheSelectedPhotoPartAndPreservesItsAspectRatio() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "photo-1",
          "title": "Vacation",
          "type": "photo",
          "thumb": "/library/metadata/photo-1/thumb/12",
          "Media": [
            {
              "width": 1200,
              "height": 1200,
              "Part": [{ "key": "/library/parts/first/file.jpeg" }]
            },
            {
              "selected": "1",
              "width": "6000",
              "height": "4000",
              "Part": [
                { "key": "/library/parts/unselected/file.jpeg" },
                { "selected": true, "key": "/library/parts/selected/file.jpeg" }
              ]
            }
          ]
        }
        """#)

        let presentation = try #require(PlexPhotoPresentation(item: item))
        #expect(presentation.sourcePath == "/library/parts/selected/file.jpeg")
        #expect(presentation.fallbackArtworkPath == "/library/metadata/photo-1/thumb/12")
        #expect(presentation.pixelWidth == 6_000)
        #expect(presentation.pixelHeight == 4_000)
        #expect(presentation.dimensionsText == "6,000 × 4,000")
        #expect(presentation.fittedSize(in: CGSize(width: 900, height: 700)) == CGSize(
            width: 900,
            height: 600
        ))
        #expect(presentation.requestPixelSize(
            for: CGSize(width: 900, height: 600),
            displayScale: 2
        ) == CGSize(width: 1_800, height: 1_200))
    }

    @Test func usesServerArtworkWhenTheOriginalPartIsUnavailable() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "photo-2",
          "title": "Scanned Photo",
          "type": "photo",
          "thumb": "/library/metadata/photo-2/thumb/12"
        }
        """#)

        let presentation = try #require(PlexPhotoPresentation(item: item))
        #expect(presentation.sourcePath == "/library/metadata/photo-2/thumb/12")
        #expect(presentation.fallbackArtworkPath == nil)
        #expect(presentation.fittedSize(in: CGSize(width: 900, height: 700)) == CGSize(
            width: 900,
            height: 700
        ))
    }

    @Test func photosNeverEnterTheAVPlaybackPipeline() throws {
        let photo = try decodeItem(#"""
        {
          "ratingKey": "photo-3",
          "title": "Photo",
          "type": "photo",
          "Media": [{
            "container": "jpeg",
            "Part": [{ "key": "/library/parts/700/file.jpeg" }]
          }]
        }
        """#)
        let movie = try decodeItem(#"""
        {
          "ratingKey": "movie-1",
          "title": "Movie",
          "type": "movie",
          "Media": [{
            "container": "mp4",
            "videoCodec": "h264",
            "Part": [{ "key": "/library/parts/701/file.mp4" }]
          }]
        }
        """#)

        #expect(!photo.supportsNativePlayback)
        #expect(!photo.isPlayable)
        #expect(photo.defaultPlaybackSource == nil)
        #expect(photo.playbackSource(mediaIndex: 0) == nil)
        #expect(movie.supportsNativePlayback)
        #expect(movie.isPlayable)
        #expect(movie.defaultPlaybackSource == PlexPlaybackSource(mediaIndex: 0, partIndex: 0))
    }

    @Test func rejectsNonPhotoMetadataButKeepsAPlaceholderPresentationForAnEmptyPhoto() throws {
        let movie = try decodeItem(#"""
        { "ratingKey": "movie-1", "title": "Movie", "type": "movie", "thumb": "/thumb" }
        """#)
        let emptyPhoto = try decodeItem(#"""
        { "ratingKey": "photo-4", "title": "Photo", "type": "photo" }
        """#)

        #expect(PlexPhotoPresentation(item: movie) == nil)
        let emptyPresentation = try #require(PlexPhotoPresentation(item: emptyPhoto))
        #expect(emptyPresentation.sourcePath == nil)
        #expect(emptyPresentation.fallbackArtworkPath == nil)
    }

    private func decodeItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }
}
