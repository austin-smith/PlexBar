import PlexMockData
import Foundation
import Testing
@testable import PlexBar

#if DEBUG
@Suite struct PlexDebugMockServerTests {
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
        let nonce = try await authClient.fetchJWTNonce(clientContext: clientContext)
        let refreshedToken = try await authClient.exchangeDeviceJWT(
            "signed.device.jwt",
            clientContext: clientContext
        )

        #expect(authenticatedUser.displayName == "D0loresH4ze")
        #expect(authenticatedUser.displayEmail == "d0loresh4ze@proton.me")
        #expect(authenticatedUser.displayUsername == nil)
        #expect(authenticatedUser.thumb?.hasPrefix("file://") == true)
        #expect(servers.count == 1)
        #expect(servers.first?.id == "debug-mock-server")
        #expect(nonce == "plexbar-mock-nonce")
        #expect(refreshedToken == PlexDebugMockServer.mockUserToken)
    }

    @Test func mockAuthenticatedUserAvatarLoadsAtRequestedSizesAfterCacheEviction() async throws {
        let session = PlexDebugMockServer.makeSession()
        let authClient = PlexAuthClient(session: session)
        let authenticatedUser = try await authClient.fetchAuthenticatedUser(
            userToken: PlexDebugMockServer.mockUserToken,
            clientContext: PlexClientContext(clientIdentifier: "tests")
        )
        let thumbURL = try #require(authenticatedUser.thumb.flatMap(URL.init(string:)))
        let imageClient = PlexImageClient(
            cache: PlexImageMemoryCache(imageCountLimit: 1),
            requestCoordinator: PlexImageRequestCoordinator()
        )

        #expect(thumbURL.isFileURL)
        #expect(thumbURL.lastPathComponent == "darlene-alderson.png")
        // The second size evicts the first. The third load must read the file again.
        for size in [60, 120, 60] {
            #expect(imageClient.cachedCGImageResult(from: [thumbURL], token: "", maximumPixelSize: size) == nil)
            let result = try #require(await imageClient.fetchCGImageResult(
                from: [thumbURL],
                token: "",
                clientContext: PlexClientContext(clientIdentifier: "tests"),
                maximumPixelSize: size
            ))
            #expect(result.sourceURL == thumbURL)
            #expect(result.image.width == size)
            #expect(result.image.height == size)
        }
    }

    @Test func loadsMockServerPayloadFromResources() throws {
        let payload = try PlexMockServerPayload.loadDefault()
        let catalog = try PlexMockMediaCatalog.loadDefault()
        let hasTommyAudiobookSession = payload.activeSessions.contains { session in
            session.userID == 15 && session.mediaType == "track" && session.mediaID == "32301"
        }
        let historyCountsByUser = Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: payload.historyEvents, by: \.userID)
                .map { ($0.key, $0.value.count) }
        )

        #expect(payload.server.name == "Mock Server")
        #expect(payload.activeSessions.count == 4)
        #expect(payload.libraries.map(\.title) == ["Movies", "TV Shows", "Audiobooks"])
        let userNames = [
            "scully", "Elliot", "petit_prince", "popeye23", "TommyS", "D0loresH4ze", "scrump-toggins", "TheBaumer", "Le0n", "Joi"
        ]
        #expect(payload.users.map(\.name) == userNames)
        #expect(payload.users.first(where: { $0.id == 17 })?.avatar == "/mock/avatars/scrump-toggins.png")
        #expect(payload.historyEvents.filter { $0.userID == 17 }.count == 3)
        #expect(historyCountsByUser == [11: 4, 12: 3, 13: 1, 14: 2, 15: 3, 16: 2, 17: 3, 18: 3, 19: 3, 20: 3])
        #expect(payload.historyEvents.contains(where: { $0.mediaType == "episode" }))
        #expect(hasTommyAudiobookSession)
        #expect(payload.activeSessions.first(where: { $0.sessionKey == "stream-4" })?.audioStream?.id == 3_103_001)
        #expect(payload.activeSessions.first(where: { $0.sessionKey == "stream-4" })?.audioStream?.levels.count == 96)
        #expect(catalog.records.filter { $0.item.type == "episode" }.count == 32)
        #expect(catalog.records.filter { $0.item.type == "show" }.count == 12)
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
        #expect(librariesByTitle["Movies"]?.latestItemTitle == "All Quiet on the Western Front")
        #expect(librariesByTitle["TV Shows"]?.type == .show)
        #expect(librariesByTitle["TV Shows"]?.itemCount == 12)
        #expect(librariesByTitle["TV Shows"]?.secondaryCount == 18)
        #expect(librariesByTitle["TV Shows"]?.secondaryCountLabel == "seasons")
        #expect(librariesByTitle["TV Shows"]?.latestItemTitle == "One Step Beyond")
        #expect(librariesByTitle["Audiobooks"]?.type == .artist)
        #expect(librariesByTitle["Audiobooks"]?.itemCount == 8)
        #expect(librariesByTitle["Audiobooks"]?.secondaryCount == 10)
        #expect(librariesByTitle["Audiobooks"]?.secondaryCountLabel == "albums")
        #expect(librariesByTitle["Audiobooks"]?.latestItemTitle == "Alexandre Dumas")
    }

    @Test func mockServerFiltersLibrarySearchByTitle() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let configuration = PlexConnectionConfiguration(
            serverURL: URL(string: "https://demo.plexbar.local:32400")!,
            token: "plexbar-debug-mock-server-token",
            clientContext: PlexClientContext(clientIdentifier: "tests")
        )
        let libraries = try await client.fetchLibraries(using: configuration)
        let movies = try #require(libraries.first(where: { $0.title == "Movies" }))

        let page = try await client.fetchMediaPage(
            libraryID: movies.id,
            using: configuration,
            searchQuery: "night"
        )

        #expect(page.items.map(\.title) == ["Night of the Living Dead"])
        #expect(page.totalSize == 1)
    }

    @Test func mockServerDescribesAndAppliesLibrarySorts() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let configuration = PlexConnectionConfiguration(
            serverURL: URL(string: "https://demo.plexbar.local:32400")!,
            token: "plexbar-debug-mock-server-token",
            clientContext: PlexClientContext(clientIdentifier: "tests")
        )
        let libraries = try await client.fetchLibraries(using: configuration)
        let movies = try #require(libraries.first { $0.title == "Movies" })
        let endpoints = try await client.fetchLibraryProviderEndpoints(using: configuration)
        let route = try #require(endpoints.browseRoute(for: movies.id))
        let definition = try await client.fetchLibraryBrowseDefinition(
            sectionPath: route.sectionPath,
            contentPath: route.contentPath,
            using: configuration
        )
        let nameSort = try #require(definition.sorts.first { $0.id == "titleSort" })
        let descendingName = try #require(nameSort.selection(direction: .descending))

        let page = try await client.fetchMediaPage(
            contentPath: definition.contentPath,
            using: configuration,
            browseOptions: PlexLibraryBrowseOptions(sort: descendingName)
        )

        #expect(definition.booleanFilters.map(\.id) == ["unwatched", "inProgress"])
        #expect(definition.sorts.map(\.title) == ["Name", "Date Added"])
        #expect(page.items.map(\.title) == ["The Stranger", "The Phantom of the Opera", "The Lost World", "The Little Shop of Horrors", "The Last Man on Earth", "The General", "The Bat", "Sherlock Jr.", "Reefer Madness", "Plan 9 from Outer Space", "Nosferatu", "Night of the Living Dead", "My Man Godfrey", "Metropolis", "It's a Wonderful Life", "Fear and Desire", "Charade", "Animal Crackers", "All Quiet on the Western Front", "A Star Is Born"])
    }

    @Test func mockServerReturnsBrowsableCollectionsAndPlaylists() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let configuration = PlexConnectionConfiguration(
            serverURL: URL(string: "https://demo.plexbar.local:32400")!,
            token: "plexbar-debug-mock-server-token",
            clientContext: PlexClientContext(clientIdentifier: "tests")
        )
        let libraries = try await client.fetchLibraries(using: configuration)
        let movies = try #require(libraries.first { $0.title == "Movies" })
        let collections = try await client.fetchCollectionsPage(
            libraryID: movies.id,
            using: configuration
        )
        let collection = try #require(collections.items.first)
        let collectionItems = try await client.fetchMediaChildren(
            of: collection,
            using: configuration
        )
        let playlists = try await client.fetchPlaylistsPage(
            endpointPath: "/playlists",
            using: configuration
        )
        let videoPlaylist = try #require(playlists.items.first { $0.playlistType == "video" })
        let playlistItems = try await client.fetchMediaChildren(
            of: videoPlaylist,
            using: configuration
        )

        #expect(collection.title == "Movies Collection")
        #expect(collection.childrenPath == "/library/collections/9101/items")
        #expect(collectionItems.items.map(\.title) == ["All Quiet on the Western Front", "Animal Crackers", "Charade", "Night of the Living Dead", "Sherlock Jr.", "Nosferatu", "Metropolis", "The Lost World", "The General", "The Phantom of the Opera", "The Little Shop of Horrors", "A Star Is Born", "My Man Godfrey", "The Stranger", "Plan 9 from Outer Space", "It's a Wonderful Life", "Fear and Desire", "The Bat", "The Last Man on Earth", "Reefer Madness"])
        #expect(playlists.items.map(\.title) == ["Video Playlist", "Audio Playlist"])
        #expect(videoPlaylist.childrenPath == "/playlists/9201/items")
        #expect(playlistItems.items.allSatisfy { $0.playlistItemID != nil })
    }

    @Test func mockServerReturnsPromotedHomeHubsAndTheirExactContentKeys() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let configuration = PlexConnectionConfiguration(
            serverURL: URL(string: "https://demo.plexbar.local:32400")!,
            token: "plexbar-debug-mock-server-token",
            clientContext: PlexClientContext(clientIdentifier: "tests")
        )
        let endpoints = try await client.fetchLibraryProviderEndpoints(using: configuration)
        let promotedPath = try #require(endpoints.promotedPath)
        let hubs = try await client.fetchHubs(
            endpointPath: promotedPath,
            using: configuration,
            count: 2
        )
        let moviesHub = try #require(hubs.first { $0.title == "Recently Added Movies" })
        let path = try #require(moviesHub.key)
        let page = try await client.fetchMediaPage(
            contentPath: path,
            using: configuration,
            start: 0,
            size: 2
        )

        #expect(hubs.map(\.title) == [
            "Recently Added Movies",
            "Recently Added TV Shows",
            "Recently Added Audiobooks"
        ])
        #expect(moviesHub.metadata.count == 2)
        #expect(moviesHub.more)
        #expect(path == "/hubs/home/recentlyAdded?type=1")
        #expect(page.items.map(\.title) == ["All Quiet on the Western Front", "Animal Crackers"])
        #expect(page.totalSize == 20)
    }

    @Test func mockServerServesTranscodedPosterArtwork() async throws {
        let session = PlexDebugMockServer.makeSession()
        let imageClient = PlexImageClient(session: session)
        let clientContext = PlexClientContext(clientIdentifier: "tests")
        let posterURL = try #require(PlexURLBuilder.transcodedArtworkURL(
            serverURL: URL(string: "https://demo.plexbar.local:32400")!,
            path: "/mock/art/movies/charade/poster.png",
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
        #expect(tommySession.title == "Book 1, Chapter 1")
        #expect(tommySession.duration == 939_000)
        #expect(tommySession.parentThumb == "/mock/art/audiobooks/war-of-the-worlds/cover.png")
        #expect(tommySession.thumb == "/mock/art/audiobooks/war-of-the-worlds/cover.png")
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

    @Test func mockProfilesResolveTheSameDevicesInActivityAndHistory() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let payload = try PlexMockServerPayload.loadDefault()
        let directory = try await client.fetchHistoryIdentityDirectory(using: configuration)
        let sessions = try await client.fetchSessions(using: configuration)
        let history = try await client.fetchHistory(using: configuration, since: .distantPast)
        let devicesByID = Dictionary(uniqueKeysWithValues: directory.devices.map { ($0.id, $0) })
        #expect(directory.devices.count == payload.users.flatMap(\.devices).count)
        for event in history where event.deviceID != nil {
            #expect(event.playbackDevice(using: devicesByID) != nil)
        }
        for activity in payload.activeSessions {
            let device = try #require(devicesByID[activity.deviceID])
            let session = try #require(sessions.first { $0.canonicalSessionKey == activity.sessionKey })
            #expect(session.player.title == device.name)
            #expect(session.player.platform == device.platform)
            #expect(session.player.state == activity.state)
        }
    }

    private var configuration: PlexConnectionConfiguration {
        PlexConnectionConfiguration(
            serverURL: PlexDebugMockServer.mockResolvedConnection.url,
            token: PlexDebugMockServer.mockServer.accessToken,
            clientContext: PlexClientContext(clientIdentifier: "catalog-tests")
        )
    }

    @Test func everyLibraryRootResolvesRichDetailsAndItsCompleteHierarchy() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let endpoints = try await client.fetchLibraryProviderEndpoints(using: configuration)
        let libraries = try await client.fetchLibraries(using: configuration)
        for library in libraries {
            let route = try #require(endpoints.browseRoute(for: library.id))
            let page = try await client.fetchMediaPage(contentPath: route.contentPath, using: configuration)
            #expect(page.totalSize == page.items.count)
            for root in page.items {
                #expect(root.type != nil)
                #expect(root.librarySectionID == library.id)
                let detail = try await client.fetchMediaMetadata(ratingKey: root.ratingKey, using: configuration)
                #expect(detail == root)
                #expect(detail.summary?.isEmpty == false)
                if detail.hasChildren {
                    let children = try await client.fetchMediaChildren(of: detail, using: configuration)
                    #expect(children.items.count == detail.childCount)
                    for child in children.items {
                        #expect(child.parentRatingKey == detail.ratingKey)
                        let firstPage = try await client.fetchMediaChildren(of: child, using: configuration)
                        let totalSize = try #require(firstPage.totalSize)
                        var leaves = firstPage.items
                        while leaves.count < totalSize {
                            let nextPage = try await client.fetchMediaChildren(
                                of: child, using: configuration, start: leaves.count
                            )
                            try #require(!nextPage.items.isEmpty)
                            leaves += nextPage.items
                        }
                        #expect(!leaves.isEmpty)
                        #expect(leaves.count == child.leafCount)
                        #expect(Set(leaves.map(\.ratingKey)).count == leaves.count)
                        for leaf in leaves {
                            #expect(leaf.parentRatingKey == child.ratingKey)
                            #expect(leaf.grandparentRatingKey == detail.ratingKey)
                            #expect(leaf.duration.map { $0 > 0 } == true)
                            let refreshed = try await client.fetchMediaMetadata(ratingKey: leaf.ratingKey, using: configuration)
                            #expect(refreshed == leaf)
                        }
                    }
                }
            }
        }
    }

    @Test func filmDetailsRetainVerifiedCreditsRatingsAndReleaseMetadata() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let film = try await client.fetchMediaMetadata(ratingKey: "1101", using: configuration)
        #expect(film.title == "Charade")
        #expect(film.year == 1963)
        #expect(film.originallyAvailableAt == "1963-12-05")
        #expect(film.duration == 6_780_000)
        #expect(film.directors.map(\.tag) == ["Stanley Donen"])
        #expect(film.roles.contains { $0.tag == "Audrey Hepburn" && $0.role == "Regina Lampert" })
        #expect(film.art != film.thumb)
        #expect(PlexExternalRatingsPresentation(item: film, locale: Locale(identifier: "en_US"))
            .ratings.first { $0.source == .rottenTomatoes }?.displayValue == "95%")
        #expect(film.progress != nil)
    }

    @Test func sourcedIMDbRatingsProduceLinksToTheMatchingTitles() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let expected = [
            ("1101", "tt0056923", "7.8"), ("1102", "tt0063350", "7.8"),
            ("1103", "tt0015324", "8.1"), ("2101", "tt0052442", "7.8"),
            ("2102", "tt0044230", "7.4"), ("2103", "tt0044229", "8.1"),
            ("2201", "tt0507807", "7.1"), ("2204", "tt0507795", "7.1"),
            ("2205", "tt0507773", "6.6"), ("2203", "tt0504552", "7.7")
        ]
        for (ratingKey, identifier, score) in expected {
            let item = try await client.fetchMediaMetadata(ratingKey: ratingKey, using: configuration)
            let presentation = PlexExternalRatingsPresentation(item: item, locale: Locale(identifier: "en_US"))
            let rating = try #require(presentation.ratings.first { $0.source == .imdb })
            #expect(rating.displayValue == score)
            #expect(rating.destinationURL?.absoluteString == "https://www.imdb.com/title/\(identifier)/")
        }
        // A verified episode score must not link to its parent show's IMDb page.
        let david = try await client.fetchMediaMetadata(ratingKey: "2202", using: configuration)
        let rating = try #require(PlexExternalRatingsPresentation(item: david).ratings.first { $0.source == .imdb })
        #expect(rating.destinationURL == nil)
    }

    @Test func correctedEpisodeIdentitiesAreSharedWithHistory() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let bride = try await client.fetchMediaMetadata(ratingKey: "2201", using: configuration)
        #expect(bride.index == 1)
        #expect(bride.parentIndex == 1)
        let david = try await client.fetchMediaMetadata(ratingKey: "2202", using: configuration)
        #expect(david.title == "David the Babysitter")
        #expect(david.index == 7)
        #expect(david.originallyAvailableAt == "1952-11-14")
        let dentist = try await client.fetchMediaMetadata(ratingKey: "2203", using: configuration)
        #expect(dentist.title == "The Dentist's Office")
        #expect(dentist.index == 2)
        #expect(dentist.originallyAvailableAt == "1952-12-12")
        let history = try await client.fetchHistory(
            using: configuration, since: .distantPast, metadataItemID: 2102, pageSize: 1
        )
        #expect(!history.isEmpty)
        #expect(history.allSatisfy { $0.ratingKey == david.ratingKey && $0.title == david.title })
        let futureHistory = try await client.fetchHistory(using: configuration, since: .distantFuture)
        #expect(futureHistory.isEmpty)
    }

    @Test func advertisedPlaylistsLoadTracksWithDistinctItemIdentities() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let endpoints = try await client.fetchLibraryProviderEndpoints(using: configuration)
        #expect(!endpoints.supportsPlayQueues)
        #expect(!endpoints.supportsTimeline)
        #expect(!endpoints.supportsPlaylistManagement)
        let path = try #require(endpoints.playlistPath)
        let playlists = try await client.fetchPlaylistsPage(endpointPath: path, using: configuration)
        let audio = try #require(playlists.items.first { $0.playlistType == "audio" })
        let trackCount = try #require(audio.leafCount)
        let tracks = try await client.fetchMediaChildren(of: audio, using: configuration, size: trackCount)
        #expect(tracks.items.count == trackCount)
        #expect(tracks.items.allSatisfy { $0.type == "track" && $0.playlistItemID != nil })
        #expect(Set(tracks.items.map(\.id)).count == tracks.items.count)
        for playlist in playlists.items {
            let detail = try await client.fetchMediaMetadata(ratingKey: playlist.ratingKey, using: configuration)
            #expect(detail == playlist)
        }
    }

    @Test func advertisedSearchPagesPreserveQueriesAndBoundaries() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let endpoints = try await client.fetchLibraryProviderEndpoints(using: configuration)
        let path = try #require(endpoints.searchPath)
        let hubs = try await client.fetchSearchHubs(query: "H. G. Wells", endpointPath: path, using: configuration, limit: 2)
        let tracks = try #require(hubs.first { $0.type == "track" })
        #expect(tracks.metadata.count == 2)
        #expect(tracks.more)
        let next = try await client.fetchMediaPage(
            contentPath: try #require(tracks.key), using: configuration, start: 2, size: 2
        )
        #expect(next.items.count == 2)
        #expect(next.totalSize == tracks.totalSize)
        #expect(Set(next.items.map(\.id)).isDisjoint(with: tracks.metadata.map(\.id)))
        let empty = try await client.fetchSearchHubs(query: "no matching title", endpointPath: path, using: configuration)
        #expect(empty.isEmpty)
    }

    @Test func watchFiltersAgreeWithContinueWatchingAndPaginationTotals() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let endpoints = try await client.fetchLibraryProviderEndpoints(using: configuration)
        let hubs = try await client.fetchHomeHubs(endpoints: endpoints, using: configuration, count: 1)
        let continuation = try #require(hubs.first { $0.isContinueWatching })
        #expect(continuation.metadata.count == 1)
        #expect(continuation.more)
        let all = try await client.fetchMediaPage(contentPath: try #require(continuation.key), using: configuration)
        #expect(all.items.allSatisfy { ($0.viewOffset ?? 0) > 0 && !$0.isWatched })
        let moviesPath = try #require(endpoints.browseRoute(for: "library-movies")?.contentPath)
        let unwatched = try await client.fetchMediaPage(
            contentPath: moviesPath, using: configuration,
            browseOptions: PlexLibraryBrowseOptions(enabledBooleanFilterIDs: ["unwatched"])
        )
        #expect(unwatched.items.map(\.ratingKey) == ["1110", "1119", "1120", "1101", "1115", "1114", "1105", "1111", "1102", "1104", "1113", "1118", "1116", "1107", "1117", "1109", "1106", "1108", "1112"])
        #expect(unwatched.totalSize == 19)
        let progressing = try await client.fetchMediaPage(
            contentPath: moviesPath, using: configuration,
            browseOptions: PlexLibraryBrowseOptions(enabledBooleanFilterIDs: ["inProgress"])
        )
        #expect(progressing.items.map(\.ratingKey) == ["1101"])
        #expect(progressing.totalSize == 1)
    }

    @Test func relatedExtrasAndPeopleResolveTheirOwnContracts() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let film = try await client.fetchMediaMetadata(ratingKey: "1101", using: configuration)
        let related = try await client.fetchRelatedHubs(ratingKey: film.ratingKey, using: configuration, count: 1)
        let hub = try #require(related.first)
        #expect(hub.more)
        let page = try await client.fetchMediaPage(contentPath: try #require(hub.key), using: configuration, start: 1, size: 1)
        #expect(page.items.first?.ratingKey != hub.metadata.first?.ratingKey)
        let extras = try await client.fetchMediaExtras(ratingKey: film.ratingKey, using: configuration)
        #expect(extras.count == 1)
        #expect(extras.first?.type == "clip")
        #expect(extras.first?.subtype == "trailer")
        let emptyExtras = try await client.fetchMediaExtras(ratingKey: "1102", using: configuration)
        #expect(emptyExtras.isEmpty)
        let personID = try #require(film.roles.first?.tagKey)
        let person = try await client.fetchPerson(identifier: personID, using: configuration)
        #expect(person.tag == film.roles.first?.tag)
        let appearances = try await client.fetchPersonMedia(identifier: personID, using: configuration)
        #expect(appearances.map(\.ratingKey) == [film.ratingKey])
    }

    @Test func mockRejectsUnknownRoutesAndWriteMethodsWithoutNetworkForwarding() async throws {
        let session = PlexDebugMockServer.makeSession()
        for (path, method, expected) in [
            ("/library/metadata/1101/refresh", "GET", 404),
            ("/library/metadata/1101/extras/invalid", "GET", 404),
            ("/library/metadata/missing", "GET", 404),
            ("/playlists", "POST", 405),
            ("/status/sessions/terminate", "GET", 405),
            ("/video/:/transcode/universal/decision", "GET", 404)
        ] {
            var request = URLRequest(url: configuration.serverURL.appending(path: path))
            request.httpMethod = method
            let (data, response) = try await session.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == expected)
            #expect(String(decoding: data, as: UTF8.self).contains("Mock data does not support"))
        }
        let (_, response) = try await session.data(from: URL(string: "https://unhandled.invalid/missing")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 404)
    }

    @Test func catalogSourcesAndCountsValidateWithoutCreatingPlaybackSources() throws {
        let catalog = try PlexMockMediaCatalog.loadDefault()
        #expect(catalog.records.allSatisfy { !$0.sources.isEmpty && !$0.item.isPlayable })
        let payload = try PlexMockServerPayload.loadDefault()
        let artworkPaths = Set(payload.artwork.map(\.path))
        #expect(artworkPaths.count == payload.artwork.count)
        for record in catalog.records {
            let item = record.item
            let paths = [item.thumb, item.art, item.parentThumb, item.grandparentThumb].compactMap { $0 }
            #expect(paths.allSatisfy { artworkPaths.contains($0) })
        }
        for artwork in payload.artwork {
            let data = try Data(contentsOf: PlexMockServerResourceLocator.url(for: artwork.resource))
            #expect(!data.isEmpty)
        }
        for album in catalog.records where album.item.type == "album" {
            let tracks = catalog.children(of: album.item.ratingKey)
            #expect(album.item.duration == tracks.reduce(0) { $0 + ($1.item.duration ?? 0) })
            #expect(tracks.allSatisfy { $0.item.parentTitle == album.item.title })
        }
        let data = try Data(contentsOf: PlexMockServerResourceLocator.url(for: "media-catalog.json"))
        var entries = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        entries[0]["relatedIDs"] = ["missing"]
        let broken = try JSONSerialization.data(withJSONObject: entries)
        #expect(throws: PlexMockMediaCatalog.CatalogError.self) {
            try PlexMockMediaCatalog(data: broken)
        }
    }
}
#endif
