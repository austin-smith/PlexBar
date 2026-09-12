import Foundation
import Testing
@testable import PlexBar

struct PlexEpisodeContinuityTests {
    @Test
    func nextEpisodeUsesLibraryOrderRatherThanResponseOrder() throws {
        let current = try item(ratingKey: "episode-2", type: "episode", index: 2)
        let values = try [
            item(ratingKey: "episode-4", type: "episode", index: 4),
            item(ratingKey: "featurette", type: "clip", index: 3),
            item(ratingKey: "episode-3", type: "episode", index: 3),
            current,
        ]

        let next = PlexEpisodeContinuity.nextEpisode(after: current, in: values)

        #expect(next?.ratingKey == "episode-3")
    }

    @Test
    func nextEpisodeFallsForwardWhenCurrentEpisodeIsMissing() throws {
        let current = try item(ratingKey: "missing", type: "episode", index: 2)
        let values = try [
            item(ratingKey: "episode-1", type: "episode", index: 1),
            item(ratingKey: "episode-3", type: "episode", index: 3),
        ]

        let next = PlexEpisodeContinuity.nextEpisode(after: current, in: values)

        #expect(next?.ratingKey == "episode-3")
    }

    @Test
    func nextSeasonCrossesToTheFirstLaterSeason() throws {
        let seasons = try [
            item(ratingKey: "season-3", type: "season", index: 3),
            item(ratingKey: "specials", type: "season", index: 0),
            item(ratingKey: "season-2", type: "season", index: 2),
        ]

        let next = PlexEpisodeContinuity.nextSeason(
            afterRatingKey: "season-1",
            index: 1,
            in: seasons
        )

        #expect(next?.ratingKey == "season-2")
    }

    @Test
    func nextSeasonReturnsNilAtEndOfShow() throws {
        let seasons = try [
            item(ratingKey: "season-1", type: "season", index: 1),
            item(ratingKey: "season-2", type: "season", index: 2),
        ]

        let next = PlexEpisodeContinuity.nextSeason(
            afterRatingKey: "season-2",
            index: 2,
            in: seasons
        )

        #expect(next == nil)
    }

    private func item(ratingKey: String, type: String, index: Int) throws -> PlexMediaItem {
        let value: [String: Any] = [
            "ratingKey": ratingKey,
            "key": "/library/metadata/\(ratingKey)",
            "type": type,
            "title": ratingKey,
            "index": index,
            "Media": [],
        ]
        return try JSONDecoder().decode(
            PlexMediaItem.self,
            from: JSONSerialization.data(withJSONObject: value)
        )
    }
}
