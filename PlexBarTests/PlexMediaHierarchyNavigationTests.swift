import PlexModels
import Foundation
import Testing
@testable import PlexBar

@Suite
struct PlexMediaHierarchyNavigationTests {
    @Test func episodeUsesExactShowAndSeasonIdentifiers() throws {
        let episode = try decodeItem(#"""
        {
          "ratingKey": "102",
          "title": "Episode",
          "type": "episode",
          "parentRatingKey": "101",
          "parentTitle": "Season 2",
          "grandparentRatingKey": "100",
          "grandparentTitle": "The Show"
        }
        """#)

        #expect(episode.hierarchyDestinations.map(\.relationship) == [.show, .season])
        #expect(episode.hierarchyDestinations.map(\.title) == ["The Show", "Season 2"])
        #expect(episode.hierarchyDestinations.map(\.route.ratingKey) == ["100", "101"])
    }

    @Test func trackUsesExactArtistAndAlbumIdentifiers() throws {
        let track = try decodeItem(#"""
        {
          "ratingKey": "202",
          "title": "Track",
          "type": "track",
          "parentRatingKey": "201",
          "parentTitle": "The Album",
          "grandparentRatingKey": "200",
          "grandparentTitle": "The Artist"
        }
        """#)

        #expect(track.hierarchyDestinations.map(\.relationship) == [.artist, .album])
        #expect(track.hierarchyDestinations.map(\.title) == ["The Artist", "The Album"])
        #expect(track.hierarchyDestinations.map(\.route.ratingKey) == ["200", "201"])
    }

    @Test func episodeSkipsSeasonNavigationWhenPlexAdvertisesSkipParent() throws {
        let episode = try decodeItem(#"""
        {
          "ratingKey": "102",
          "title": "Episode",
          "type": "episode",
          "parentRatingKey": "101",
          "parentTitle": "Season 1",
          "grandparentRatingKey": "100",
          "grandparentTitle": "The Show",
          "skipParent": "1"
        }
        """#)

        #expect(episode.skipParent == true)
        #expect(episode.hierarchyDestinations.map(\.relationship) == [.show])
        #expect(episode.hierarchyDestinations.map(\.title) == ["The Show"])
        #expect(episode.hierarchyDestinations.map(\.route.ratingKey) == ["100"])
    }

    @Test func skipParentDoesNotInventAReplacementHierarchyDestination() throws {
        let episode = try decodeItem(#"""
        {
          "ratingKey": "102",
          "title": "Episode",
          "type": "episode",
          "parentRatingKey": "101",
          "parentTitle": "Season 1",
          "skipParent": true
        }
        """#)

        #expect(episode.skipParent == true)
        #expect(episode.hierarchyDestinations.isEmpty)
    }

    @Test func hierarchyNavigationDoesNotGuessMissingOrSelfReferentialRoutes() throws {
        let episode = try decodeItem(#"""
        {
          "ratingKey": "102",
          "title": "Episode",
          "type": "episode",
          "parentRatingKey": "102",
          "parentTitle": "Self",
          "grandparentTitle": "Missing ID"
        }
        """#)

        #expect(episode.hierarchyDestinations.isEmpty)
    }

    @Test func metadataRefreshRetainsTheExactBrowseHierarchyPath() throws {
        let browseItem = try decodeItem(#"{"ratingKey":"100","key":"/library/metadata/100/children?includeGuids=1","type":"show","title":"Show"}"#)
        let details = try decodeItem(#"{"ratingKey":"100","type":"show","title":"Show","summary":"Details"}"#)

        let requestItem = browseItem.hierarchyRequestItem(afterRefreshingWith: details)

        #expect(requestItem == browseItem)
        #expect(requestItem.childrenPath == "/library/metadata/100/children?includeGuids=1")
    }

    @Test func metadataRefreshSuppliesHierarchyPathWhenTheOriginalRouteHasNone() throws {
        let unresolvedItem = try decodeItem(#"{"ratingKey":"100","type":"show","title":"Show"}"#)
        let details = try decodeItem(#"{"ratingKey":"100","key":"/library/metadata/100/children","type":"show","title":"Show"}"#)

        let requestItem = unresolvedItem.hierarchyRequestItem(afterRefreshingWith: details)

        #expect(requestItem == details)
        #expect(requestItem.childrenPath == "/library/metadata/100/children")
    }

    private func decodeItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }
}
