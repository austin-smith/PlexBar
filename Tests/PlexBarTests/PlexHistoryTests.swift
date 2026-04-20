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
        2: PlexAccount(id: 2, name: "test-user", thumb: nil),
    ]
    let seriesByEpisodeID = [
        "2001": PlexHistorySeriesIdentity(
            id: "show-search-party",
            title: "Search Party",
            posterPath: "/library/metadata/show-thumb"
        ),
        "2002": PlexHistorySeriesIdentity(
            id: "show-search-party",
            title: "Search Party",
            posterPath: "/library/metadata/show-thumb"
        ),
    ]
    let topTitles = PlexHistoryAnalytics.topTitleEntries(
        from: [firstEpisode, secondEpisode, movie],
        accountsByID: accountsByID,
        seriesByEpisodeID: seriesByEpisodeID,
        limit: 3
    )

    #expect(topTitles.first?.title == "Search Party")
    #expect(topTitles.first?.playCount == 2)
    #expect(topTitles.first?.posterPath == "/library/metadata/show-thumb")
    #expect(topTitles.first?.subtitle == "2 recent plays across 2 episodes")
    #expect(topTitles.first?.watcherSummary == "myveryownsarah")
    #expect(topTitles.first?.watcherAccountIDs == [1])
    #expect(topTitles.first?.coverageLabel == "2 episodes")
    #expect(topTitles.first?.viewerCountLabel == "1 viewer")
    #expect(topTitles.last?.title == "Heat")
}

@Test func filtersTopTitleChartsToMoviesOnly() async throws {
    let episode = PlexHistoryItem(
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
    let movie = PlexHistoryItem(
        historyKey: "/status/sessions/history/2",
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

    let topTitles = PlexHistoryAnalytics.topTitleEntries(
        from: [episode, movie],
        accountsByID: [:],
        seriesByEpisodeID: [
            "2001": PlexHistorySeriesIdentity(
                id: "show-search-party",
                title: "Search Party",
                posterPath: "/library/metadata/show-thumb"
            )
        ],
        limit: 5,
        filter: .movies
    )

    #expect(topTitles.count == 1)
    #expect(topTitles.first?.title == "Heat")
}

@Test func filtersTopTitleChartsToTVOnly() async throws {
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
    let movie = PlexHistoryItem(
        historyKey: "/status/sessions/history/2",
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

    let topTitles = PlexHistoryAnalytics.topTitleEntries(
        from: [firstEpisode, movie],
        accountsByID: [:],
        seriesByEpisodeID: [
            "2001": PlexHistorySeriesIdentity(
                id: "show-search-party",
                title: "Search Party",
                posterPath: "/library/metadata/show-thumb"
            )
        ],
        limit: 5,
        filter: .tv
    )

    #expect(topTitles.count == 1)
    #expect(topTitles.first?.title == "Search Party")
}

@Test func filtersRecentItemsBeforeApplyingPreviewLimit() async throws {
    let movie = PlexHistoryItem(
        historyKey: "/status/sessions/history/100",
        key: "/library/metadata/3100",
        ratingKey: "3100",
        title: "Heat",
        type: "movie",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "1995-12-15",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_000),
        accountID: 1
    )

    let episodes = (0..<12).map { offset in
        PlexHistoryItem(
            historyKey: "/status/sessions/history/\(offset)",
            key: "/library/metadata/20\(offset)",
            ratingKey: "20\(offset)",
            title: "Episode \(offset)",
            type: "episode",
            thumb: nil,
            parentThumb: nil,
            grandparentThumb: nil,
            art: nil,
            grandparentTitle: "Search Party",
            parentTitle: "Season 1",
            parentIndex: 1,
            index: offset + 1,
            originallyAvailableAt: "2016-11-21",
            viewedAt: Date(timeIntervalSince1970: 1_700_000_100 + Double(offset)),
            accountID: 1
        )
    }

    let recentMovies = PlexHistoryAnalytics.recentItems(
        from: episodes + [movie],
        filter: .movies,
        limit: 10
    )

    #expect(recentMovies.count == 1)
    #expect(recentMovies.first?.title == "Heat")
}

@Test func groupsRawHistoryRowsIntoSharedWatchEvents() async throws {
    let firstRow = PlexHistoryItem(
        historyKey: "/status/sessions/history/1",
        key: "/library/metadata/3001",
        ratingKey: "3001",
        title: "Heat",
        type: "movie",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "1995-12-15",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_000),
        accountID: 2,
        deviceID: 55
    )
    let secondRow = PlexHistoryItem(
        historyKey: "/status/sessions/history/2",
        key: "/library/metadata/3001",
        ratingKey: "3001",
        title: "Heat",
        type: "movie",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "1995-12-15",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_300),
        accountID: 2,
        deviceID: 55
    )

    let groupedItems = PlexHistoryAnalytics.groupedWatchItems(from: [firstRow, secondRow])

    #expect(groupedItems.count == 1)
    #expect(groupedItems.first?.historyKey == "/status/sessions/history/2")
}

@Test func topTitleChartsCountGroupedWatchesInsteadOfRawRows() async throws {
    let firstRow = PlexHistoryItem(
        historyKey: "/status/sessions/history/1",
        key: "/library/metadata/3001",
        ratingKey: "3001",
        title: "Heat",
        type: "movie",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "1995-12-15",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_000),
        accountID: 2,
        deviceID: 55
    )
    let secondRow = PlexHistoryItem(
        historyKey: "/status/sessions/history/2",
        key: "/library/metadata/3001",
        ratingKey: "3001",
        title: "Heat",
        type: "movie",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "1995-12-15",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_300),
        accountID: 2,
        deviceID: 55
    )
    let thirdRow = PlexHistoryItem(
        historyKey: "/status/sessions/history/3",
        key: "/library/metadata/3001",
        ratingKey: "3001",
        title: "Heat",
        type: "movie",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "1995-12-15",
        viewedAt: Date(timeIntervalSince1970: 1_700_086_400),
        accountID: 2,
        deviceID: 55
    )

    let groupedItems = PlexHistoryAnalytics.groupedWatchItems(from: [firstRow, secondRow, thirdRow])
    let topTitles = PlexHistoryAnalytics.topTitleEntries(
        from: groupedItems,
        accountsByID: [2: PlexAccount(id: 2, name: "russy52", thumb: nil)],
        seriesByEpisodeID: [:],
        limit: 5
    )

    #expect(topTitles.count == 1)
    #expect(topTitles.first?.playCount == 2)
    #expect(topTitles.first?.watcherSummary == "russy52")
    #expect(topTitles.first?.watcherAccountIDs == [2])
}

@Test func topTitleChartsRankWatcherAccountIDsByPlaysThenName() async throws {
    let first = PlexHistoryItem(
        historyKey: "/status/sessions/history/1",
        key: "/library/metadata/3001",
        ratingKey: "3001",
        title: "Heat",
        type: "movie",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "1995-12-15",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_000),
        accountID: 3
    )
    let second = PlexHistoryItem(
        historyKey: "/status/sessions/history/2",
        key: "/library/metadata/3001",
        ratingKey: "3001",
        title: "Heat",
        type: "movie",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "1995-12-15",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_100),
        accountID: 1
    )
    let third = PlexHistoryItem(
        historyKey: "/status/sessions/history/3",
        key: "/library/metadata/3001",
        ratingKey: "3001",
        title: "Heat",
        type: "movie",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "1995-12-15",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_200),
        accountID: 1
    )
    let fourth = PlexHistoryItem(
        historyKey: "/status/sessions/history/4",
        key: "/library/metadata/3001",
        ratingKey: "3001",
        title: "Heat",
        type: "movie",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        originallyAvailableAt: "1995-12-15",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_300),
        accountID: 2
    )

    let topTitles = PlexHistoryAnalytics.topTitleEntries(
        from: [first, second, third, fourth],
        accountsByID: [
            1: PlexAccount(id: 1, name: "anna", thumb: nil),
            2: PlexAccount(id: 2, name: "zoe", thumb: nil),
            3: PlexAccount(id: 3, name: "mike", thumb: nil),
        ],
        seriesByEpisodeID: [:],
        limit: 5
    )

    #expect(topTitles.first?.watcherSummary == "anna, mike, zoe")
    #expect(topTitles.first?.watcherAccountIDs == [1, 3, 2])
}

@Test func keepsDistinctSeriesSeparateWhenTitlesMatch() async throws {
    let firstSeriesEpisode = PlexHistoryItem(
        historyKey: "/status/sessions/history/101",
        key: "/library/metadata/4101",
        ratingKey: "4101",
        title: "Pilot",
        type: "episode",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: "/library/metadata/us-office-thumb",
        art: nil,
        grandparentTitle: "The Office",
        parentTitle: "Season 1",
        parentIndex: 1,
        index: 1,
        originallyAvailableAt: "2005-03-24",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_000),
        accountID: 1
    )
    let secondSeriesEpisode = PlexHistoryItem(
        historyKey: "/status/sessions/history/102",
        key: "/library/metadata/4201",
        ratingKey: "4201",
        title: "Downsize",
        type: "episode",
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: "/library/metadata/uk-office-thumb",
        art: nil,
        grandparentTitle: "The Office",
        parentTitle: "Season 1",
        parentIndex: 1,
        index: 1,
        originallyAvailableAt: "2001-07-09",
        viewedAt: Date(timeIntervalSince1970: 1_700_000_100),
        accountID: 2
    )

    let topTitles = PlexHistoryAnalytics.topTitleEntries(
        from: [firstSeriesEpisode, secondSeriesEpisode],
        accountsByID: [:],
        seriesByEpisodeID: [
            "4101": PlexHistorySeriesIdentity(
                id: "show-office-us",
                title: "The Office",
                posterPath: "/library/metadata/us-office-thumb"
            ),
            "4201": PlexHistorySeriesIdentity(
                id: "show-office-uk",
                title: "The Office",
                posterPath: "/library/metadata/uk-office-thumb"
            ),
        ],
        limit: 5
    )

    #expect(topTitles.count == 2)
    #expect(Set(topTitles.map(\.id)) == ["tv:show-office-us", "tv:show-office-uk"])
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
