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

@Test func localSessionsStillExposeGeoLookupAddressWhenPlexProvidesPublicIP() async throws {
    let json = #"""
    {
      "sessionKey": "77",
      "ratingKey": "146",
      "key": "/library/metadata/146",
      "type": "episode",
      "title": "Local Stream",
      "Player": {
        "title": "MacBook Air",
        "address": "192.168.1.226",
        "remotePublicAddress": "97.115.180.233",
        "local": true,
        "relayed": false,
        "secure": true
      },
      "Session": {
        "id": "77",
        "location": "lan"
      }
    }
    """#

    let data = try #require(json.data(using: .utf8))
    let session = try JSONDecoder().decode(PlexSession.self, from: data)

    #expect(session.player.remotePublicAddress == "97.115.180.233")
    #expect(session.player.local == true)
    #expect(session.player.relayed == false)
    #expect(session.player.secure == true)
    #expect(session.geoLookupIPAddress == "97.115.180.233")
}

@Test func decodesAudioStreamIDFromSessionPayload() async throws {
    let json = #"""
    {
      "sessionKey": "77",
      "ratingKey": "49928",
      "key": "/library/metadata/49928",
      "type": "track",
      "title": "Apple in China",
      "Player": {
        "title": "Prologue",
        "state": "playing"
      },
      "Media": [
        {
          "id": 114191,
          "audioCodec": "aac",
          "Part": [
            {
              "id": 125260,
              "Stream": [
                {
                  "id": 384686,
                  "streamType": 2,
                  "codec": "aac",
                  "selected": 1
                }
              ]
            }
          ]
        }
      ]
    }
    """#

    let data = try #require(json.data(using: .utf8))
    let session = try JSONDecoder().decode(PlexSession.self, from: data)

    #expect(session.contentKind == .track)
    #expect(session.audioStreamID == 384686)
}

@Test func audioStreamIDPrefersSelectedAudioStream() async throws {
    let session = PlexSession(
        ratingKey: "49928",
        key: "/library/metadata/49928",
        type: "track",
        subtype: nil,
        live: false,
        title: "Apple in China",
        grandparentTitle: "Patrick McGee",
        parentTitle: "Apple in China",
        parentIndex: nil,
        index: nil,
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
        media: [
            PlexMedia(part: [
                PlexPart(decision: nil, stream: [
                    PlexStream(id: 100, streamType: 2, codec: "aac", selected: false),
                    PlexStream(id: 200, streamType: 2, codec: "aac", selected: true),
                ])
            ])
        ]
    )

    #expect(session.audioStreamID == 200)
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

@Test func playbackTimingSummaryFormatsRemainingMinutesAndEndTime() async throws {
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
        duration: 1_377_000,
        viewOffset: 905_000,
        year: 1995,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: "playing", title: nil),
        session: nil,
        media: nil
    )

    let timeZone = try #require(TimeZone(secondsFromGMT: 0))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let referenceDate = try #require(calendar.date(from: DateComponents(
        timeZone: timeZone,
        year: 2026,
        month: 4,
        day: 13,
        hour: 18,
        minute: 23,
        second: 8
    )))

    let summary = session.playbackTimingSummary(
        referenceDate: referenceDate,
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: timeZone
    )

    #expect(summary?.replacingOccurrences(of: "\u{202F}", with: " ") == "8 min left (6:31 PM)")
}

@Test func playbackTimingSummaryFormatsHourAndMinuteRemainder() async throws {
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
        duration: 5_400_000,
        viewOffset: 1_500_000,
        year: 1995,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: "playing", title: nil),
        session: nil,
        media: nil
    )

    let timeZone = try #require(TimeZone(secondsFromGMT: 0))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let referenceDate = try #require(calendar.date(from: DateComponents(
        timeZone: timeZone,
        year: 2026,
        month: 4,
        day: 13,
        hour: 17,
        minute: 36,
        second: 0
    )))

    let summary = session.playbackTimingSummary(
        referenceDate: referenceDate,
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: timeZone
    )

    #expect(summary?.replacingOccurrences(of: "\u{202F}", with: " ") == "1 hr 5 min left (6:41 PM)")
}

@Test func playbackTimingSummaryOmitsLiveAndIncompleteSessions() async throws {
    let referenceDate = Date(timeIntervalSince1970: 0)

    let liveSession = PlexSession(
        ratingKey: "42",
        key: "/livetv/sessions/42",
        type: "episode",
        subtype: nil,
        live: true,
        title: "Heat",
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        duration: 1_377_000,
        viewOffset: 905_000,
        year: 1995,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: "playing", title: nil),
        session: nil,
        media: nil
    )

    let incompleteSession = PlexSession(
        ratingKey: "43",
        key: "/library/metadata/43",
        type: "movie",
        subtype: nil,
        live: false,
        title: "Collateral",
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        thumb: nil,
        parentThumb: nil,
        grandparentThumb: nil,
        art: nil,
        duration: nil,
        viewOffset: 905_000,
        year: 2004,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: "playing", title: nil),
        session: nil,
        media: nil
    )

    #expect(liveSession.playbackTimingSummary(referenceDate: referenceDate) == nil)
    #expect(incompleteSession.playbackTimingSummary(referenceDate: referenceDate) == nil)
}

@Test func playbackTimingSummaryOmitsCompletionTimeWhenPaused() async throws {
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
        duration: 1_377_000,
        viewOffset: 905_000,
        year: 1995,
        user: nil,
        player: PlexPlayer(address: nil, machineIdentifier: nil, platform: nil, product: nil, state: "paused", title: nil),
        session: nil,
        media: nil
    )

    let referenceDate = Date(timeIntervalSince1970: 0)
    let summary = session.playbackTimingSummary(referenceDate: referenceDate)

    #expect(summary == "8 min left")
}
