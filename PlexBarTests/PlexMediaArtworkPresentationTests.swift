import PlexModels
import Foundation
import Testing
@testable import PlexBar

struct PlexMediaArtworkPresentationTests {
    @Test func episodeBrowserAndHomeUseTheirDifferentPlexArtworkContracts() throws {
        let episode = try item(#"{"ratingKey":"1","type":"episode","title":"Episode","thumb":"/episode.jpg","parentThumb":"/season.jpg","grandparentThumb":"/show.jpg"}"#)
        let browser = PlexMediaArtworkPresentation(item: episode)
        let home = PlexMediaArtworkPresentation(item: episode, layout: .poster)
        #expect(browser.shape == .landscape)
        #expect(browser.path == "/episode.jpg")
        #expect(home.shape == .poster)
        #expect(home.path == "/show.jpg")
    }

    @Test func seasonCardsKeepTheSeasonPosterRatherThanRepeatingTheSeriesPoster() throws {
        let season = try item(#"{"ratingKey":"2","type":"season","title":"Season 2","thumb":"/season-2.jpg","parentThumb":"/show.jpg"}"#)
        let card = PlexMediaArtworkPresentation(item: season)
        #expect(card.shape == .poster)
        #expect(card.path == "/season-2.jpg")
    }

    @Test func missingSeriesPosterDoesNotCropAnEpisodeThumbnailIntoAPoster() throws {
        let episode = try item(#"{"ratingKey":"1","type":"episode","title":"Episode","thumb":"/episode.jpg"}"#)
        #expect(PlexMediaArtworkPresentation(item: episode, layout: .poster).path == nil)
    }

    @Test(arguments: ["artist", "album", "track", "photo", "photoalbum", "collection", "playlist"])
    func squareMediaKeepsMacOSArtworkShape(type: String) throws {
        let media = try item(#"{"ratingKey":"3","type":"\#(type)","title":"Media","thumb":"/art.jpg"}"#)
        let card = PlexMediaArtworkPresentation(item: media)
        #expect(card.shape == .square)
        #expect(card.path == "/art.jpg")
    }

    private func item(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }
}
