import Foundation
import Testing
@testable import PlexBar

@Test func prefersSeriesPosterForEpisodeHistoryItems() async throws {
    let item = PlexHistoryItem(
        historyKey: "/status/sessions/history/12",
        key: "/library/metadata/146",
        ratingKey: "146",
        title: "Syzygy",
        type: "episode",
        thumb: "/library/metadata/episode-thumb",
        parentThumb: "/library/metadata/season-thumb",
        grandparentThumb: "/library/metadata/show-thumb",
        art: "/library/metadata/show-art",
        grandparentTitle: "The X-Files",
        parentTitle: "Season 3",
        parentIndex: 3,
        index: 13,
        originallyAvailableAt: "1996-01-26",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_000),
        accountID: 42
    )

    #expect(item.posterPath == "/library/metadata/show-thumb")
    #expect(item.headline == "The X-Files")
    #expect(item.detailLine == "S3E13 • Syzygy")
}

@Test func aggregatesTopTitleChartsBySeriesNameForEpisodes() async throws {
    let firstEpisode = PlexHistoryItem(
        historyKey: "/status/sessions/history/1",
        key: "/library/metadata/2001",
        ratingKey: "2001",
        title: "Pilot",
        type: "episode",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: "/library/metadata/show-thumb",
        art: nil,
        grandparentTitle: "Search Party",
        parentTitle: "Season 1",
        parentIndex: 1,
        index: 1,
        originallyAvailableAt: "2016-11-21",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_000),
        accountID: 1
    )
    let secondEpisode = PlexHistoryItem(
        historyKey: "/status/sessions/history/2",
        key: "/library/metadata/2002",
        ratingKey: "2002",
        title: "The Mysterious Disappearance of the Girl No One Knew",
        type: "episode",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: "/library/metadata/show-thumb",
        art: nil,
        grandparentTitle: "Search Party",
        parentTitle: "Season 1",
        parentIndex: 1,
        index: 2,
        originallyAvailableAt: "2016-11-21",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_100),
        accountID: 1
    )
    let movie = PlexHistoryItem(
        historyKey: "/status/sessions/history/3",
        key: "/library/metadata/3001",
        ratingKey: "3001",
        title: "Heat",
        type: "movie",
        thumb: "/library/metadata/heat-thumb",
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "1995-12-15",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_200),
        accountID: 2
    )

    let accountsByID = [
        1: PlexAccount(id: 1, name: "myveryownsarah", thumb: nil),
        2: PlexAccount(id: 2, name: "smitty_", thumb: nil),
    ]
    let topTitles = PlexHistoryAnalytics.topTitleEntries(
        from: [firstEpisode, secondEpisode, movie],
        accountsByID: accountsByID,
        limit: 3
    )

    #expect(topTitles.first?.title == "Search Party")
    #expect(topTitles.first?.playCount == 2)
    #expect(topTitles.first?.posterPath == "/library/metadata/show-thumb")
    #expect(topTitles.first?.subtitle == "2 recent plays across 2 episodes")
    #expect(topTitles.first?.watcherSummary == "myveryownsarah")
    #expect(topTitles.first?.coverageLabel == "2 episodes")
    #expect(topTitles.first?.viewerCountLabel == "1 viewer")
    #expect(topTitles.last?.title == "Heat")
}

@Test func decodesViewedAtTimestampFromHistoryPayload() async throws {
    let json = #"""
    {
      "historyKey": "/status/sessions/history/9",
      "key": "/library/metadata/500",
      "ratingKey": "500",
      "title": "Bob's Burgers",
      "type": "episode",
      "grandparentTitle": "Bob's Burgers",
      "viewedAt": 1712452410
    }
    """#

    let data = try #require(json.data(using: .utf8))
    let item = try JSONDecoder().decode(PlexHistoryItem.self, from: data)

    #expect(item.id == "/status/sessions/history/9")
    #expect(item.viewedAt != nil)
    #expect(item.headline == "Bob's Burgers")
}

@Test func resolvesWatcherNameFromAccountLookup() async throws {
    let item = PlexHistoryItem(
        historyKey: "/status/sessions/history/22",
        key: "/library/metadata/22",
        ratingKey: "22",
        title: "The Immortal Man",
        type: "movie",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "2025-01-01",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_000),
        accountID: 77
    )

    let watcher = item.watcherName(using: [
        77: PlexAccount(id: 77, name: "alexcaro3", thumb: nil)
    ])

    #expect(watcher == "alexcaro3")
}
