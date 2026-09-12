import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexMediaProviderTests {
    @Test func decodesLibraryTimelineEndpointsFromAdvertisedProviderFeatures() throws {
        let envelope = try JSONDecoder().decode(
            PlexMediaProvidersEnvelope.self,
            from: mediaProvidersData()
        )

        #expect(try envelope.mediaContainer.libraryProviderEndpoints() == providerEndpoints)
        #expect(envelope.mediaContainer.allowSync == true)
    }

    @Test func decodesPlayQueueIndependentlyFromTimelineMutationPaths() throws {
        let data = Data(#"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"timeline","key":"/timeline-only"},{"type":"playqueue","key":"/queue-only"}]}]}}"#.utf8)
        let envelope = try JSONDecoder().decode(PlexMediaProvidersEnvelope.self, from: data)
        let endpoints = try envelope.mediaContainer.libraryProviderEndpoints()

        #expect(endpoints.timelinePath == "/timeline-only")
        #expect(endpoints.scrobblePath == nil)
        #expect(endpoints.unscrobblePath == nil)
        #expect(endpoints.playQueuePath == "/queue-only")
        #expect(endpoints.supportsTimeline)
        #expect(!endpoints.supportsWatchedStateMutation)
        #expect(endpoints.supportsPlayQueues)
    }

    @Test func decodesAdvertisedPlaylistEndpointAndProviderWriteAccess() throws {
        let writableData = Data(#"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"playlist","key":"/provider/playlists?source=library","readOnly":false}]}]}}"#.utf8)
        let readOnlyData = Data(#"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"playlist","key":"/shared/playlists","readonly":true}]}]}}"#.utf8)

        let writable = try JSONDecoder()
            .decode(PlexMediaProvidersEnvelope.self, from: writableData)
            .mediaContainer
            .libraryProviderEndpoints()
        let readOnly = try JSONDecoder()
            .decode(PlexMediaProvidersEnvelope.self, from: readOnlyData)
            .mediaContainer
            .libraryProviderEndpoints()

        #expect(writable.playlistPath == "/provider/playlists?source=library")
        #expect(writable.supportsPlaylists)
        #expect(writable.supportsPlaylistManagement)
        #expect(readOnly.playlistPath == "/shared/playlists")
        #expect(readOnly.supportsPlaylists)
        #expect(!readOnly.supportsPlaylistManagement)
    }

    @Test func collectionManagementRequiresEveryAdvertisedProviderCapability() throws {
        let completeData = Data(#"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"collection","key":"/provider/collections?source=library"},{"type":"metadata","key":"/provider/metadata?source=library"},{"type":"manage"}]}]}}"#.utf8)
        let missingCollectionData = Data(#"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"metadata","key":"/provider/metadata"},{"type":"manage"}]}]}}"#.utf8)

        let complete = try JSONDecoder()
            .decode(PlexMediaProvidersEnvelope.self, from: completeData)
            .mediaContainer
            .libraryProviderEndpoints()
        let missingCollection = try JSONDecoder()
            .decode(PlexMediaProvidersEnvelope.self, from: missingCollectionData)
            .mediaContainer
            .libraryProviderEndpoints()

        #expect(complete.collectionPath == "/provider/collections?source=library")
        #expect(complete.supportsCollectionManagement)
        #expect(!missingCollection.supportsCollectionManagement)
    }

    @Test func rejectsProviderResponseWithoutTheLibraryProvider() throws {
        let data = Data(#"{"MediaContainer":{"MediaProvider":[{"identifier":"another.provider","Feature":[]}]}}"#.utf8)
        let envelope = try JSONDecoder().decode(PlexMediaProvidersEnvelope.self, from: data)

        #expect(throws: PlexAPIError.self) {
            try envelope.mediaContainer.libraryProviderEndpoints()
        }
    }

    @MainActor
    @Test func watchedMutationUsesDiscoveredEndpointsRefreshesCachesAndCachesProviderContract() async throws {
        let suiteName = "PlexBarTests.watchedMutationUsesDiscoveredEndpoints"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let scenario = WatchedMutationScenario()
        let session = makeMediaProviderMockSession { request in
            try scenario.response(for: request)
        }
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(
                credentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
            ),
            initialCredentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
        )
        settings.selectedServerIdentifier = "server-id"
        settings.selectedServerName = "Server"
        let connectionStore = PlexConnectionStore(settings: settings)
        connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "server-id",
            url: try #require(URL(string: "https://plex.local:32400")),
            kind: .local,
            validatedAt: Date()
        )
        let store = PlexBrowserStore(
            connectionStore: connectionStore,
            client: PlexAPIClient(session: session)
        )

        await store.loadHomeHubs()
        let initialItem = try #require(store.homeHubs.first?.metadata.first)
        #expect(!initialItem.isWatched)

        let watchedItem = try await store.setWatched(true, for: initialItem)
        #expect(watchedItem.isWatched)
        #expect(store.homeHubs.first?.metadata.first?.isWatched == true)

        let unwatchedItem = try await store.setWatched(false, for: watchedItem)
        #expect(!unwatchedItem.isWatched)
        #expect(store.homeHubs.first?.metadata.first?.isWatched == false)
        #expect(!store.isUpdatingWatchedState(for: unwatchedItem))
        #expect(scenario.requestCount(for: "/media/providers") == 1)
        #expect(scenario.requestCount(for: "/provider/played") == 1)
        #expect(scenario.requestCount(for: "/provider/unplayed") == 1)
    }

    @MainActor
    @Test func downloadAuthorizationIsScopedToThePresentedServerConnection() async throws {
        let suiteName = "PlexBarTests.downloadAuthorizationConnectionScope"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let scenario = WatchedMutationScenario()
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(
                credentials: PlexStoredCredentials(
                    userToken: "user-token",
                    serverToken: "server-token"
                )
            ),
            initialCredentials: PlexStoredCredentials(
                userToken: "user-token",
                serverToken: "server-token"
            )
        )
        settings.selectedServerIdentifier = "server-id"
        settings.selectedServerName = "Server"
        let connectionStore = PlexConnectionStore(settings: settings)
        connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "server-id",
            url: try #require(URL(string: "https://plex.local:32400")),
            kind: .local,
            validatedAt: Date()
        )
        let store = PlexBrowserStore(
            connectionStore: connectionStore,
            client: PlexAPIClient(session: makeMediaProviderMockSession { request in
                try scenario.response(for: request)
            })
        )
        let user = PlexAuthenticatedUser(
            id: 42,
            username: "test-user",
            title: nil,
            email: nil,
            thumb: nil,
            friendlyName: nil,
            subscriptions: [PlexUserSubscription(
                type: "plexpass",
                state: "active",
                mode: "recurring",
                active: true,
                subscribedAt: nil
            )]
        )

        let library = mediaProviderDownloadLibrary()
        #expect(store.downloadAuthorization(for: user, library: library) == nil)
        await store.loadLibraryProviderCapabilities()
        #expect(store.downloadAuthorization(for: user, library: library)?.isAuthorized == true)

        connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "different-server",
            url: try #require(URL(string: "https://other-plex.local:32400")),
            kind: .remote,
            validatedAt: Date()
        )
        #expect(store.downloadAuthorization(for: user, library: library) == nil)
    }

    @MainActor
    @Test func providerCapabilitiesAreScopedToTheExactPMSTokenWithoutCachingTheSecret() async throws {
        let suiteName = "PlexBarTests.providerCapabilitiesCredentialScope"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstToken = "first-server-token"
        let secondToken = "second-server-token"
        let scenario = CredentialScopedProviderScenario(
            writableToken: firstToken,
            writableProviderData: Self.mediaProvidersData()
        )
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(
                credentials: PlexStoredCredentials(
                    userToken: "user-token",
                    serverToken: firstToken
                )
            ),
            initialCredentials: PlexStoredCredentials(
                userToken: "user-token",
                serverToken: firstToken
            )
        )
        settings.selectedServerIdentifier = "server-id"
        settings.selectedServerName = "Server"
        let connectionStore = PlexConnectionStore(settings: settings)
        let serverURL = try #require(URL(string: "https://plex.local:32400"))
        connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "server-id",
            url: serverURL,
            kind: .local,
            validatedAt: Date()
        )
        let store = PlexBrowserStore(
            connectionStore: connectionStore,
            client: PlexAPIClient(session: makeMediaProviderMockSession { request in
                try scenario.response(for: request)
            })
        )

        await store.loadLibraryProviderCapabilities()
        #expect(store.supportsCollectionManagement)

        settings.serverToken = secondToken
        await store.loadLibraryProviderCapabilities()
        #expect(!store.supportsCollectionManagement)

        settings.serverToken = firstToken
        await store.loadLibraryProviderCapabilities()
        #expect(store.supportsCollectionManagement)
        #expect(scenario.providerRequestCount == 2)

        let firstScope = PlexConnectionConfiguration.authenticationCacheScope(for: firstToken)
        let secondScope = PlexConnectionConfiguration.authenticationCacheScope(for: secondToken)
        #expect(firstScope != secondScope)
        #expect(!firstScope.contains(firstToken))
        #expect(!secondScope.contains(secondToken))
    }

    @MainActor
    @Test func personalRatingAndMetadataRefreshUseAdvertisedCapabilities() async throws {
        let suiteName = "PlexBarTests.personalRatingAndMetadataRefresh"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let scenario = WatchedMutationScenario()
        let session = makeMediaProviderMockSession { request in
            try scenario.response(for: request)
        }
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(
                credentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
            ),
            initialCredentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
        )
        settings.selectedServerIdentifier = "server-id"
        settings.selectedServerName = "Server"
        let connectionStore = PlexConnectionStore(settings: settings)
        connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "server-id",
            url: try #require(URL(string: "https://plex.local:32400")),
            kind: .local,
            validatedAt: Date()
        )
        let store = PlexBrowserStore(
            connectionStore: connectionStore,
            client: PlexAPIClient(session: session)
        )

        await store.loadHomeHubs()
        await store.loadLibraryProviderCapabilities()
        let initialItem = try #require(store.homeHubs.first?.metadata.first)
        #expect(store.supportsPersonalRatings)
        #expect(store.supportsMetadataRefresh(for: initialItem))

        let ratedItem = try await store.setPersonalRating(8, for: initialItem)
        #expect(ratedItem.userRating == 8)
        #expect(store.homeHubs.first?.metadata.first?.userRating == 8)

        let clearedItem = try await store.setPersonalRating(nil, for: ratedItem)
        #expect(clearedItem.userRating == nil)
        #expect(store.homeHubs.first?.metadata.first?.userRating == nil)

        try await store.refreshMetadata(for: clearedItem)
        #expect(!store.isRefreshingMetadata(for: clearedItem))
        #expect(scenario.requestCount(for: "/media/providers") == 1)
        #expect(scenario.requestCount(for: "/provider/rate") == 2)
        #expect(scenario.requestCount(for: "/provider/metadata/42/refresh") == 1)
    }

    @MainActor
    @Test func continueWatchingRemovalUsesAdvertisedActionAndUpdatesOnlyThatHub() async throws {
        let suiteName = "PlexBarTests.continueWatchingRemoval"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let scenario = WatchedMutationScenario()
        let session = makeMediaProviderMockSession { request in
            try scenario.response(for: request)
        }
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(
                credentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
            ),
            initialCredentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
        )
        settings.selectedServerIdentifier = "server-id"
        settings.selectedServerName = "Server"
        let connectionStore = PlexConnectionStore(settings: settings)
        connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "server-id",
            url: try #require(URL(string: "https://plex.local:32400")),
            kind: .local,
            validatedAt: Date()
        )
        let store = PlexBrowserStore(
            connectionStore: connectionStore,
            client: PlexAPIClient(session: session)
        )

        await store.loadHomeHubs()
        await store.loadLibraryProviderCapabilities()
        let continueWatchingHub = try #require(
            store.homeState.hubs.first(where: { $0.isContinueWatching })
        )
        let initialItem = try #require(continueWatchingHub.metadata.first)
        await store.loadHomeHubItems(in: continueWatchingHub)

        #expect(store.supportsRemoveFromContinueWatching)
        #expect(store.homeHubItems(in: continueWatchingHub).map(\.ratingKey) == ["42", "43"])

        try await store.removeFromContinueWatching(initialItem)

        let updatedContinueWatchingHub = try #require(
            store.homeState.hubs.first(where: { $0.isContinueWatching })
        )
        let recentlyAddedHub = try #require(
            store.homeState.hubs.first(where: { $0.hubIdentifier == "movie.recentlyadded.1" })
        )
        #expect(updatedContinueWatchingHub.metadata.allSatisfy { $0.ratingKey != "42" })
        #expect(store.homeHubItems(in: updatedContinueWatchingHub).map(\.ratingKey) == ["43"])
        #expect(recentlyAddedHub.metadata.contains(where: { $0.ratingKey == "42" }))
        #expect(!store.isRemovingFromContinueWatching(initialItem))
        #expect(scenario.requestCount(for: "/provider/remove-from-continue") == 1)
    }

    @MainActor
    @Test func continuousQueueUsesTheProviderAdvertisedPlayQueueEndpoint() async throws {
        let suiteName = "PlexBarTests.continuousQueueUsesAdvertisedEndpoint"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let scenario = WatchedMutationScenario(providerData: Self.playQueueOnlyMediaProvidersData())
        let session = makeMediaProviderMockSession { request in
            try scenario.response(for: request)
        }
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(
                credentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
            ),
            initialCredentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
        )
        settings.selectedServerIdentifier = "server-id"
        settings.selectedServerName = "Server"
        let connectionStore = PlexConnectionStore(settings: settings)
        connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "server-id",
            url: try #require(URL(string: "https://plex.local:32400")),
            kind: .local,
            validatedAt: Date()
        )
        let store = PlexBrowserStore(
            connectionStore: connectionStore,
            client: PlexAPIClient(session: session)
        )
        let item = try decodeItem(#"{"ratingKey":"82","key":"/library/metadata/82","type":"track","title":"Chapter 2"}"#)

        let queue = try await store.continuousPlayQueue(for: item)
        let page = try await store.refreshPlayQueueWindow(
            queueID: queue.id,
            centeredOn: try #require(queue.currentItem.playQueueItemID)
        )

        #expect(queue.currentItem.ratingKey == "82")
        #expect(page.id == 92)
        #expect(page.selectedItemID == "602")
        #expect(scenario.requestCount(for: "/media/providers") == 1)
        #expect(scenario.requestCount(for: "/provider/play-queue") == 1)
        #expect(scenario.requestCount(for: "/provider/play-queue/92") == 1)
        #expect(!store.supportsWatchedStateMutation(for: item))

        try await store.markPlayedIfSupported(ratingKey: item.ratingKey)

        #expect(scenario.requestCount(for: "/media/providers") == 1)
        #expect(scenario.requestCount(for: "/provider/played") == 0)
    }

    @Test func watchedStateMergePreservesContextSpecificListIdentity() throws {
        let playlistItem = try decodeItem(#"{"ratingKey":"42","playlistItemID":"900","type":"movie","title":"Movie","viewCount":0}"#)
        let refreshedItem = try decodeItem(#"{"ratingKey":"42","type":"movie","title":"Movie","viewCount":1}"#)

        let merged = playlistItem.mergingWatchedState(from: refreshedItem)

        #expect(merged.id == "playlist-item:900")
        #expect(merged.isWatched)
    }

    @Test func personalRatingMergePreservesContextSpecificListIdentity() throws {
        let playlistItem = try decodeItem(#"{"ratingKey":"42","playlistItemID":"900","type":"movie","title":"Movie","userRating":3}"#)
        let refreshedItem = try decodeItem(#"{"ratingKey":"42","type":"movie","title":"Movie","userRating":9}"#)

        let merged = playlistItem.mergingUserRating(from: refreshedItem)

        #expect(merged.id == "playlist-item:900")
        #expect(merged.userRating == 9)
    }

    @Test func hierarchicalItemsAreWatchedOnlyWhenEveryLeafIsWatched() throws {
        let partiallyWatchedShow = try decodeItem(#"{"ratingKey":"7","type":"show","title":"Show","leafCount":10,"viewedLeafCount":9}"#)
        let fullyWatchedShow = try decodeItem(#"{"ratingKey":"7","type":"show","title":"Show","leafCount":10,"viewedLeafCount":10}"#)

        #expect(!partiallyWatchedShow.isWatched)
        #expect(fullyWatchedShow.isWatched)
        #expect(fullyWatchedShow.supportsWatchedStateMutation)
    }

    private var providerEndpoints: PlexLibraryProviderEndpoints {
        PlexLibraryProviderEndpoints(
            providerIdentifier: "com.plexapp.plugins.library",
            browseRoutesByLibraryID: [
                "3": PlexLibraryBrowseRoute(
                    sectionPath: "/provider/sections/3?source=library",
                    contentPath: "/provider/sections/3/all?type=1&source=library"
                )
            ],
            promotedPath: "/provider/promoted?includeTypeFirst=1",
            continueWatchingPath: "/provider/continue?source=library",
            searchPath: "/provider/search?includeCollections=1",
            timelinePath: "/provider/timeline?source=library",
            scrobblePath: "/provider/played?source=library",
            unscrobblePath: "/provider/unplayed?source=library",
            playQueuePath: "/provider/play-queue",
            ratePath: "/provider/rate?source=library",
            metadataPath: "/provider/metadata?source=library",
            removeFromContinueWatchingPath: "/provider/remove-from-continue?source=library",
            collectionPath: "/provider/collections?source=library",
            playlistPath: "/provider/playlists?source=library",
            playlistReadOnly: false,
            canManage: true,
            serverAllowsSync: true,
            supportsDownloadSubscriptions: true
        )
    }

    private func mediaProvidersData() -> Data {
        Self.mediaProvidersData()
    }

    private static func mediaProvidersData() -> Data {
        Data(#"""
        {
          "MediaContainer": {
            "allowSync": true,
            "MediaProvider": [{
              "identifier": "com.plexapp.plugins.library",
              "Feature": [{
                "type": "content",
                "key": "/provider/sections",
                "Directory": [{
                  "id": 3,
                  "key": "/provider/sections/3?source=library",
                  "type": "movie",
                  "title": "Movies",
                  "Pivot": [{
                    "id": "library",
                    "key": "/provider/sections/3/all?type=1&source=library",
                    "type": "list",
                    "title": "Library"
                  }]
                }]
              }, {
                "type": "promoted",
                "key": "/provider/promoted?includeTypeFirst=1"
              }, {
                "type": "continuewatching",
                "key": "/provider/continue?source=library"
              }, {
                "type": "search",
                "key": "/provider/search?includeCollections=1"
              }, {
                "type": "timeline",
                "key": "/provider/timeline?source=library",
                "scrobbleKey": "/provider/played?source=library",
                "unscrobbleKey": "/provider/unplayed?source=library"
              }, {
                "type": "playqueue",
                "key": "/provider/play-queue"
              }, {
                "type": "rate",
                "key": "/provider/rate?source=library"
              }, {
                "type": "metadata",
                "key": "/provider/metadata?source=library"
              }, {
                "type": "actions",
                "key": "/provider/actions",
                "Action": [{
                  "id": "removeFromContinueWatching",
                  "key": "/provider/remove-from-continue?source=library"
                }]
              }, {
                "type": "collection",
                "key": "/provider/collections?source=library"
              }, {
                "type": "playlist",
                "key": "/provider/playlists?source=library",
                "readOnly": false
              }, {
                "type": "subscribe",
                "flavor": "download"
              }, {
                "type": "manage"
              }]
            }]
          }
        }
        """#.utf8)
    }

    private static func playQueueOnlyMediaProvidersData() -> Data {
        Data(#"""
        {
          "MediaContainer": {
            "MediaProvider": [{
              "identifier": "com.plexapp.plugins.library",
              "Feature": [{
                "type": "playqueue",
                "key": "/provider/play-queue?source=library"
              }]
            }]
          }
        }
        """#.utf8)
    }

    private func decodeItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }

    private final class WatchedMutationScenario: @unchecked Sendable {
        private let lock = NSLock()
        private let providerData: Data
        private var watched = false
        private var personalRating: Double?
        private var requestCounts: [String: Int] = [:]

        init(providerData: Data = PlexMediaProviderTests.mediaProvidersData()) {
            self.providerData = providerData
        }

        func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))

            lock.lock()
            requestCounts[url.path, default: 0] += 1
            let data: Data
            switch url.path {
            case "/provider/promoted":
                data = Data(#"{"MediaContainer":{"Hub":[{"hubIdentifier":"home.continue","key":"/hubs/continue-expanded","title":"Continue Watching","more":true,"totalSize":2,"Metadata":[{"ratingKey":"42","type":"movie","title":"Movie","viewCount":0}]},{"hubIdentifier":"movie.recentlyadded.1","title":"Recently Added in Movies","Metadata":[{"ratingKey":"42","type":"movie","title":"Movie","viewCount":0}]}]}}"#.utf8)
            case "/provider/continue":
                data = Data(#"{"MediaContainer":{"Hub":[{"hubIdentifier":"continueWatching","key":"/hubs/continue-expanded","title":"Continue Watching","more":true,"totalSize":2,"Metadata":[{"ratingKey":"42","type":"movie","title":"Movie","viewCount":0}]}]}}"#.utf8)
            case "/hubs/continue-expanded":
                data = Data(#"{"MediaContainer":{"size":2,"totalSize":2,"Metadata":[{"ratingKey":"42","type":"movie","title":"Movie","viewCount":0},{"ratingKey":"43","type":"movie","title":"Another Movie","viewCount":0}]}}"#.utf8)
            case "/media/providers":
                data = providerData
            case "/provider/played":
                guard request.httpMethod == "PUT",
                      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                        .contains(where: { $0.name == "source" && $0.value == "library" }) == true else {
                    lock.unlock()
                    Issue.record("Invalid watched request: \(url.absoluteString)")
                    throw URLError(.badURL)
                }
                watched = true
                data = Data()
            case "/provider/unplayed":
                guard request.httpMethod == "PUT",
                      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                        .contains(where: { $0.name == "source" && $0.value == "library" }) == true else {
                    lock.unlock()
                    Issue.record("Invalid unwatched request: \(url.absoluteString)")
                    throw URLError(.badURL)
                }
                watched = false
                data = Data()
            case "/provider/rate":
                guard request.httpMethod == "PUT",
                      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      queryItems.contains(where: { $0.name == "source" && $0.value == "library" }),
                      let ratingValue = queryItems.first(where: { $0.name == "rating" })?.value,
                      let rating = Double(ratingValue) else {
                    lock.unlock()
                    Issue.record("Invalid personal rating request: \(url.absoluteString)")
                    throw URLError(.badURL)
                }
                personalRating = rating == 0 ? nil : rating
                data = Data()
            case "/provider/remove-from-continue":
                guard request.httpMethod == "PUT",
                      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      queryItems.contains(where: { $0.name == "source" && $0.value == "library" }),
                      queryItems.contains(where: { $0.name == "ratingKey" && $0.value == "42" }) else {
                    lock.unlock()
                    Issue.record("Invalid Continue Watching removal request: \(url.absoluteString)")
                    throw URLError(.badURL)
                }
                data = Data()
            case "/provider/play-queue":
                guard request.httpMethod == "POST",
                      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      queryItems.first(where: { $0.name == "source" })?.value == "library",
                      queryItems.first(where: { $0.name == "type" })?.value == "audio" else {
                    lock.unlock()
                    Issue.record("Invalid audio play-queue request: \(url.absoluteString)")
                    throw URLError(.badURL)
                }
                data = Data(#"{"MediaContainer":{"playQueueID":"92","playQueueTotalCount":"1","playQueueSelectedItemID":"602","playQueueSelectedItemOffset":"0","offset":"0","Metadata":[{"ratingKey":"82","key":"/library/metadata/82","type":"track","title":"Chapter 2","playQueueItemID":"602","Media":[]}]}}"#.utf8)
            case "/provider/play-queue/92":
                guard request.httpMethod == "GET",
                      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      queryItems.first(where: { $0.name == "source" })?.value == "library",
                      queryItems.first(where: { $0.name == "center" })?.value == "602",
                      queryItems.first(where: { $0.name == "includeBefore" })?.value == "1",
                      queryItems.first(where: { $0.name == "includeAfter" })?.value == "1" else {
                    lock.unlock()
                    Issue.record("Invalid play-queue window request: \(url.absoluteString)")
                    throw URLError(.badURL)
                }
                data = Data(#"{"MediaContainer":{"playQueueID":"92","playQueueTotalCount":"1","playQueueSelectedItemID":"602","playQueueSelectedItemOffset":"0","offset":"0","Metadata":[{"ratingKey":"82","key":"/library/metadata/82","type":"track","title":"Chapter 2","playQueueItemID":"602","Media":[]}]}}"#.utf8)
            case "/provider/metadata/42/refresh":
                guard request.httpMethod == "PUT",
                      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                        .contains(where: { $0.name == "source" && $0.value == "library" }) == true else {
                    lock.unlock()
                    Issue.record("Invalid metadata refresh request: \(url.absoluteString)")
                    throw URLError(.badServerResponse)
                }
                data = Data()
            case "/library/metadata/42":
                let ratingField = personalRating.map { ",\"userRating\":\($0)" } ?? ""
                data = Data(#"{"MediaContainer":{"Metadata":[{"ratingKey":"42","type":"movie","title":"Movie","viewCount":\#(watched ? 1 : 0)\#(ratingField)}]}}"#.utf8)
            default:
                lock.unlock()
                Issue.record("Unexpected request: \(url.absoluteString)")
                throw URLError(.unsupportedURL)
            }
            lock.unlock()
            return (response, data)
        }

        func requestCount(for path: String) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return requestCounts[path, default: 0]
        }
    }
}

private final class CredentialScopedProviderScenario: @unchecked Sendable {
    private let lock = NSLock()
    private let writableToken: String
    private let writableProviderData: Data
    private var requestCount = 0

    init(writableToken: String, writableProviderData: Data) {
        self.writableToken = writableToken
        self.writableProviderData = writableProviderData
    }

    var providerRequestCount: Int {
        lock.withLock { requestCount }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        try lock.withLock {
            let url = try #require(request.url)
            guard url.path == "/media/providers" else {
                Issue.record("Unexpected credential-scoped provider request: \(request)")
                throw URLError(.unsupportedURL)
            }
            requestCount += 1
            let token = request.value(forHTTPHeaderField: "X-Plex-Token")
            let data = token == writableToken
                ? writableProviderData
                : Data(#"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[]}]}}"#.utf8)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, data)
        }
    }
}

private func mediaProviderDownloadLibrary() -> PlexLibrary {
    PlexLibrary(
        id: "1",
        title: "Movies",
        type: .movie,
        compositePath: nil,
        artPath: nil,
        thumbPath: nil,
        itemCount: 1,
        secondaryCount: nil,
        secondaryCountLabel: nil,
        updatedAt: nil,
        scannedAt: nil,
        contentChangedAt: nil,
        latestAddedAt: nil,
        latestItemTitle: nil,
        allowSync: true
    )
}

private func makeMediaProviderMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    MediaProviderMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MediaProviderMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class MediaProviderMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
