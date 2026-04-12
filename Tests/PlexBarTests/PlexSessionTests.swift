import Foundation
import Testing
@testable import PlexBar

@Test func normalizesProductVersionForDisplay() async throws {
    let server = PlexServerResource(
        id: "server-123",
        name: "Home Plex",
        productVersion: "1.43.1.10611-1e34174b1",
        accessToken: "server-token",
        connections: []
    )

    #expect(server.productVersion == "1.43.1.10611-1e34174b1")
    #expect(server.displayProductVersion == "1.43.1.10611")
}

@Test func prefersSeriesPosterForEpisodeSessions() async throws {
    let session = PlexSession(
        ratingKey: "146",
        key: "/library/metadata/146",
        type: "episode",
        subtype: nil,
        live: false,
        title: "Colman Domingo; Anitta",
        grandparentTitle: "Saturday Night Live",
        parentTitle: "Season 51",
        parentIndex: 51,
        index: 17,
        thumb: "/library/metadata/episode-thumb",
        parentThumb: "/library/metadata/season-thumb",
        grandparentThumb: "/library/metadata/show-thumb",
        art: "/library/metadata/show-art",
        duration: nil,
        viewOffset: nil,
        year: nil,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: nil, title: nil),
        session: nil,
        media: nil
    )

    #expect(session.posterPath == "/library/metadata/show-thumb")
}

@Test func classifiesMovieSessionFromExplicitType() async throws {
    let session = PlexSession(
        ratingKey: "42",
        key: "/library/metadata/42",
        type: "movie",
        subtype: nil,
        live: false,
        title: "Heat",
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        duration: nil,
        viewOffset: nil,
        year: 1995,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: nil, title: nil),
        session: nil,
        media: nil
    )

    #expect(session.contentKind == .movie)
}

@Test func classifiesTelevisionSessionFromExplicitType() async throws {
    let session = PlexSession(
        ratingKey: "146",
        key: "/library/metadata/146",
        type: "episode",
        subtype: nil,
        live: false,
        title: "Colman Domingo; Anitta",
        grandparentTitle: "Saturday Night Live",
        parentTitle: "Season 51",
        parentIndex: 51,
        index: 17,
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        duration: nil,
        viewOffset: nil,
        year: nil,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: nil, title: nil),
        session: nil,
        media: nil
    )

    #expect(session.contentKind == .tv)
}

@Test func classifiesLiveTVFromExplicitLiveFlag() async throws {
    let session = PlexSession(
        ratingKey: "146",
        key: "/livetv/sessions/session-1",
        type: "episode",
        subtype: nil,
        live: true,
        title: "Colman Domingo; Anitta",
        grandparentTitle: "Saturday Night Live",
        parentTitle: "Season 51",
        parentIndex: 51,
        index: 17,
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        duration: nil,
        viewOffset: nil,
        year: nil,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: nil, title: nil),
        session: nil,
        media: nil
    )

    #expect(session.contentKind == .liveTV)
    #expect(session.isLive)
}

@Test func exposesDisplayMetadataForLiveTVKind() async throws {
    #expect(PlexSessionContentKind.liveTV.displayName == "Live TV")
    #expect(PlexSessionContentKind.liveTV.symbolName == "antenna.radiowaves.left.and.right")
    #expect(PlexSessionContentKind.liveTV.contentMetaSymbolName == "antenna.radiowaves.left.and.right")
    #expect(PlexSessionContentKind.liveTV.contentMetaLabel == "Live TV")
}

@Test func decodesIntegerLiveFlagFromSessionPayload() async throws {
    let json = #"""
    {
      "ratingKey": "146",
      "key": "/livetv/sessions/session-1",
      "type": "episode",
      "live": 1,
      "title": "Colman Domingo; Anitta",
      "grandparentTitle": "Saturday Night Live",
      "parentTitle": "Season 51",
      "parentIndex": 51,
      "index": 17,
      "Player": {
        "title": "Apple TV"
      }
    }
    """#

    let data = try #require(json.data(using: .utf8))
    let session = try JSONDecoder().decode(PlexSession.self, from: data)

    #expect(session.isLive)
    #expect(session.contentKind == PlexSessionContentKind.liveTV)
}

@Test func playbackLineOmitsPlayingStateText() async throws {
    let session = PlexSession(
        ratingKey: "42",
        key: "/library/metadata/42",
        type: "movie",
        subtype: nil,
        live: false,
        title: "Heat",
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        duration: nil,
        viewOffset: nil,
        year: 1995,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: "playing", title: nil),
        session: PlexPlaybackSession(id: nil, bandwidth: nil, location: "lan"),
        media: [PlexMedia(part: [PlexPart(decision: "transcode")])]
    )

    #expect(session.playbackLine == "Transcode • LAN")
}

@Test func playbackLineOmitsPausedStateTextAndFlagsOverlayState() async throws {
    let session = PlexSession(
        ratingKey: "42",
        key: "/library/metadata/42",
        type: "movie",
        subtype: nil,
        live: false,
        title: "Heat",
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        duration: nil,
        viewOffset: nil,
        year: 1995,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: "paused", title: nil),
        session: PlexPlaybackSession(id: nil, bandwidth: nil, location: "lan"),
        media: [PlexMedia(part: [PlexPart(decision: "directplay")])]
    )

    #expect(session.isPaused)
    #expect(session.playbackLine == "Directplay • LAN")
}

@Test func playbackLineRetainsNonDefaultStateText() async throws {
    let session = PlexSession(
        ratingKey: "42",
        key: "/library/metadata/42",
        type: "movie",
        subtype: nil,
        live: false,
        title: "Heat",
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        duration: nil,
        viewOffset: nil,
        year: 1995,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: "buffering", title: nil),
        session: PlexPlaybackSession(id: nil, bandwidth: nil, location: "wan"),
        media: [PlexMedia(part: [PlexPart(decision: "transcode")])]
    )

    #expect(!session.isPaused)
    #expect(session.playbackLine == "Buffering • Transcode • WAN")
}
