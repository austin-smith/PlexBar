import Foundation
import Testing
@testable import PlexBar

@MainActor
@Test func defaultsPollIntervalToFifteenSeconds() async throws {
    let suiteName = "PlexBarTests.defaultsPollIntervalToFifteenSeconds"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    #expect(store.pollIntervalSeconds == AppConstants.defaultPollIntervalSeconds)
}

@MainActor
@Test func clampsAndPersistsConfiguredPollInterval() async throws {
    let suiteName = "PlexBarTests.clampsAndPersistsConfiguredPollInterval"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    store.pollIntervalSeconds = 999

    #expect(store.pollIntervalSeconds == AppConstants.maximumPollIntervalSeconds)

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    #expect(reloadedStore.pollIntervalSeconds == AppConstants.maximumPollIntervalSeconds)
}

@Test func normalizesServerURLAndDropsTrailingSlash() async throws {
    let url = PlexURLBuilder.normalizeServerURL("192.168.1.25:32400/")

    #expect(url?.absoluteString == "http://192.168.1.25:32400")
}

@Test func buildsAuthenticatedArtworkURL() async throws {
    let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
    let imageURL = PlexURLBuilder.authenticatedURL(
        serverURL: serverURL,
        path: "/library/metadata/146/thumb/1715112830",
        token: "secret-token"
    )

    #expect(imageURL?.absoluteString == "http://plex.local:32400/library/metadata/146/thumb/1715112830?X-Plex-Token=secret-token")
}

@Test func buildsTranscodedArtworkURL() async throws {
    let serverURL = try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400"))
    let imageURL = PlexURLBuilder.transcodedArtworkURL(
        serverURL: serverURL,
        path: "/library/metadata/146/thumb/1715112830",
        token: "secret-token",
        width: 176,
        height: 264
    )

    #expect(imageURL?.absoluteString == "https://plex.local:32400/photo/:/transcode?url=/library/metadata/146/thumb/1715112830&width=176&height=264&minSize=1&upscale=1&format=jpeg&X-Plex-Token=secret-token")
}

@Test func buildsPlexAuthURLWithPinCode() async throws {
    let clientContext = PlexClientContext(clientIdentifier: "client-123")
    let authURL = try #require(clientContext.authURL(for: "pin-code"))
    let absoluteString = authURL.absoluteString

    #expect(absoluteString.contains("https://app.plex.tv/auth/#!?"))
    #expect(absoluteString.contains("clientID=client-123"))
    #expect(absoluteString.contains("code=pin-code"))
    #expect(absoluteString.contains("context%5Bdevice%5D%5BdeviceName%5D=Mac%20(PlexBar)"))
    #expect(!absoluteString.contains("forwardUrl="))
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
