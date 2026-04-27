import Foundation
import Testing
@testable import PlexBar

#if DEBUG
@Test func mockSessionProvidesAuthBootstrapEndpoints() async throws {
    let session = PlexDebugMockServer.makeSession()
    let authClient = PlexAuthClient(session: session)
    let clientContext = PlexClientContext(clientIdentifier: "tests")

    let authenticatedUser = try await authClient.fetchAuthenticatedUser(
        userToken: PlexDebugMockServer.mockUserToken,
        clientContext: clientContext
    )
    let servers = try await authClient.fetchServers(
        userToken: PlexDebugMockServer.mockUserToken,
        clientContext: clientContext
    )

    #expect(authenticatedUser.displayName == "D0loresH4ze")
    #expect(authenticatedUser.displayEmail == "d0loresh4ze@proton.me")
    #expect(authenticatedUser.displayUsername == nil)
    #expect(authenticatedUser.thumb?.hasPrefix("file://") == true)
    #expect(servers.count == 1)
    #expect(servers.first?.id == "debug-mock-server")
}

@Test func mockAuthenticatedUserAvatarUsesLocalMockResourceURL() async throws {
    let session = PlexDebugMockServer.makeSession()
    let authClient = PlexAuthClient(session: session)
    let authenticatedUser = try await authClient.fetchAuthenticatedUser(
        userToken: PlexDebugMockServer.mockUserToken,
        clientContext: PlexClientContext(clientIdentifier: "tests")
    )
    let thumbURL = try #require(authenticatedUser.thumb.flatMap(URL.init(string:)))
    let imageClient = PlexImageClient()

    #expect(thumbURL.isFileURL)
    #expect(thumbURL.lastPathComponent == "darlene-alderson.png")
    #expect(await imageClient.fetchImage(
        from: [thumbURL],
        token: "",
        clientContext: PlexClientContext(clientIdentifier: "tests")
    ) != nil)
}

@Test func loadsMockServerPayloadFromBundle() throws {
    let payload = try PlexMockServerPayload.loadDefault()
    let hasTommyAudiobookSession = payload.activeSessions.contains { session in
        session.userID == 15 && session.mediaType == "audiobook" && session.mediaID == "3103"
    }
    let historyCountsByUser = Dictionary(
        uniqueKeysWithValues: Dictionary(grouping: payload.historyEvents, by: \.userID)
            .map { ($0.key, $0.value.count) }
    )

    #expect(payload.server.name == "Mock Server")
    #expect(payload.activeSessions.count == 4)
    #expect(payload.libraries.map(\.title) == ["Movies", "TV Shows", "Audiobooks"])
    #expect(payload.users.map(\.name) == ["scully", "Elliot", "petit_prince", "popeye23", "TommyS", "D0loresH4ze", "scrump-toggins"])
    #expect(payload.users.last?.avatar == "/mock/avatars/scrump-toggins.png")
    #expect(payload.historyEvents.filter { $0.userID == 17 }.count == 3)
    #expect(historyCountsByUser == [11: 4, 12: 3, 13: 1, 14: 2, 15: 3, 16: 2, 17: 3])
    #expect(payload.historyEvents.contains(where: { $0.mediaType == "episode" }))
    #expect(hasTommyAudiobookSession)
    #expect(payload.activeSessions.first(where: { $0.sessionKey == "stream-4" })?.audioStream?.id == 3_103_001)
    #expect(payload.activeSessions.first(where: { $0.sessionKey == "stream-4" })?.audioStream?.levels.count == 96)
    #expect(payload.episodes.count == 3)
    #expect(payload.shows.count == 3)
}

@Test func mockServerReturnsCanonicalLibraries() async throws {
    let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
    let libraries = try await client.fetchLibraries(
        using: PlexConnectionConfiguration(
            serverURL: URL(string: "https://demo.plexbar.local:32400")!,
            token: "plexbar-debug-mock-server-token",
            clientContext: PlexClientContext(clientIdentifier: "tests")
        )
    )

    let librariesByTitle = Dictionary(uniqueKeysWithValues: libraries.map { ($0.title, $0) })

    #expect(Set(librariesByTitle.keys) == ["Movies", "TV Shows", "Audiobooks"])
    #expect(librariesByTitle["Movies"]?.type == .movie)
    #expect(librariesByTitle["Movies"]?.latestItemTitle == "Charade")
    #expect(librariesByTitle["TV Shows"]?.type == .show)
    #expect(librariesByTitle["TV Shows"]?.itemCount == 3)
    #expect(librariesByTitle["TV Shows"]?.secondaryCount == 19)
    #expect(librariesByTitle["TV Shows"]?.secondaryCountLabel == "seasons")
    #expect(librariesByTitle["TV Shows"]?.latestItemTitle == "One Step Beyond")
    #expect(librariesByTitle["Audiobooks"]?.type == .artist)
    #expect(librariesByTitle["Audiobooks"]?.itemCount == 2)
    #expect(librariesByTitle["Audiobooks"]?.secondaryCount == 3)
    #expect(librariesByTitle["Audiobooks"]?.secondaryCountLabel == "albums")
    #expect(librariesByTitle["Audiobooks"]?.latestItemTitle == "Bram Stoker")
}

@Test func mockServerServesTranscodedPosterArtwork() async throws {
    let session = PlexDebugMockServer.makeSession()
    let imageClient = PlexImageClient(session: session)
    let clientContext = PlexClientContext(clientIdentifier: "tests")
    let posterURL = try #require(PlexURLBuilder.transcodedArtworkURL(
        serverURL: URL(string: "https://demo.plexbar.local:32400")!,
        path: "/mock/art/movies/charade.png",
        width: 176,
        height: 264
    ))

    let image = await imageClient.fetchImage(
        from: [posterURL],
        token: "plexbar-debug-mock-server-token",
        clientContext: clientContext
    )

    #expect(image != nil)
}

@Test func mockServerReturnsTVHistoryAndSeriesMetadata() async throws {
    let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
    let configuration = PlexConnectionConfiguration(
        serverURL: URL(string: "https://demo.plexbar.local:32400")!,
        token: "plexbar-debug-mock-server-token",
        clientContext: PlexClientContext(clientIdentifier: "tests")
    )

    let history = try await client.fetchHistory(
        using: configuration,
        since: Date(timeIntervalSinceNow: -60 * 60 * 24 * 30)
    )
    let episodeIDs = history.compactMap(\.episodeMetadataItemID)
    let seriesByEpisodeID = try await client.fetchHistorySeriesIdentities(
        using: configuration,
        episodeIDs: episodeIDs
    )

    #expect(history.contains(where: { $0.contentKind == .tv }))
    #expect(seriesByEpisodeID["2201"]?.title == "One Step Beyond")
    #expect(seriesByEpisodeID["2202"]?.title == "The Adventures of Ozzie and Harriet")
    #expect(seriesByEpisodeID["2203"]?.title == "The Abbott and Costello Show")
}

@Test func mockServerReturnsRealAudiobookSessionShape() async throws {
    let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
    let configuration = PlexConnectionConfiguration(
        serverURL: URL(string: "https://demo.plexbar.local:32400")!,
        token: "plexbar-debug-mock-server-token",
        clientContext: PlexClientContext(clientIdentifier: "tests")
    )

    let sessions = try await client.fetchSessions(using: configuration)
    let tommySession = try #require(sessions.first(where: { $0.canonicalSessionKey == "stream-4" }))

    #expect(tommySession.type == "track")
    #expect(tommySession.grandparentTitle == "H. G. Wells")
    #expect(tommySession.parentTitle == "The War of the Worlds")
    #expect(tommySession.title == "The War of the Worlds")
    #expect(tommySession.parentThumb == "/mock/art/audiobooks/war-of-the-worlds.png")
    #expect(tommySession.thumb == "/mock/art/audiobooks/war-of-the-worlds.png")
    #expect(tommySession.player.product == "Prologue")
    #expect(tommySession.player.title == "iPhone")
    #expect(tommySession.audioStreamID == 3_103_001)
}

@Test func mockServerReturnsAudiobookStreamLevels() async throws {
    let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
    let configuration = PlexConnectionConfiguration(
        serverURL: URL(string: "https://demo.plexbar.local:32400")!,
        token: "plexbar-debug-mock-server-token",
        clientContext: PlexClientContext(clientIdentifier: "tests")
    )

    let sessions = try await client.fetchSessions(using: configuration)
    let tommySession = try #require(sessions.first(where: { $0.canonicalSessionKey == "stream-4" }))
    let streamID = try #require(tommySession.audioStreamID)
    let levels = try await client.fetchStreamLevels(
        using: configuration,
        streamID: streamID,
        subsample: 96
    )

    #expect(streamID == 3_103_001)
    #expect(levels.count == 96)
    #expect(levels.min() == -39.9)
    #expect(levels.max() == -21.2)
}

@Test func mockServerRemovesTerminatedSessions() async throws {
    let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
    let configuration = PlexConnectionConfiguration(
        serverURL: URL(string: "https://demo.plexbar.local:32400")!,
        token: "plexbar-debug-mock-server-token",
        clientContext: PlexClientContext(clientIdentifier: "tests")
    )
    let sessions = try await client.fetchSessions(using: configuration)
    let session = try #require(sessions.first)
    let sessionID = try #require(session.serverSessionID)

    try await client.terminateSession(using: configuration, sessionID: sessionID)

    let refreshedSessions = try await client.fetchSessions(using: configuration)
    #expect(refreshedSessions.contains(where: { $0.serverSessionID == sessionID }) == false)
}

#endif
