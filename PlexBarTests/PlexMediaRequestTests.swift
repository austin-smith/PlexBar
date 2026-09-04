import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexMediaRequestTests {
    @Test func promotedHubsUseTheAdvertisedEndpointAndPreserveItsQuery() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, promotedHubsData())
        }

        let hubs = try await PlexAPIClient(session: session).fetchPromotedHubs(
            endpointPath: "/provider/promoted?includeTypeFirst=1&count=4",
            using: try configuration,
            count: 24
        )

        let request = try #require(capture.request)
        let components = try #require(
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        )
        #expect(components.path == "/provider/promoted")
        #expect(components.queryItems == [
            URLQueryItem(name: "includeTypeFirst", value: "1"),
            URLQueryItem(name: "count", value: "24"),
        ])
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")

        let hub = try #require(hubs.first)
        #expect(hub.id == "home.movies.recent")
        #expect(hub.title == "Recently Added Movies")
        #expect(hub.key == "/hubs/home/recentlyAdded?type=1")
        #expect(hub.style == "shelf")
        #expect(hub.size == 1)
        #expect(hub.totalSize == 12)
        #expect(hub.more)
        #expect(hub.promoted)
        #expect(hub.metadata.map(\.title) == ["Charade"])
    }

    @Test func playbackHomeHubsPreferPosterArtworkAndEpisodeUsesShowPoster() throws {
        let data = Data(#"""
        {
          "MediaContainer": {
            "Hub": [
              {
                "hubIdentifier": "home.continue",
                "title": "Continue Watching",
                "Metadata": []
              },
              {
                "hubIdentifier": "home.onDeck",
                "title": "On Deck",
                "Metadata": [{
                  "ratingKey": "42",
                  "title": "Episode Title",
                  "type": "episode",
                  "thumb": "/library/metadata/42/thumb",
                  "parentThumb": "/library/metadata/41/thumb",
                  "grandparentThumb": "/library/metadata/40/thumb",
                  "Media": []
                }]
              },
              {
                "hubIdentifier": "home.movies.recent",
                "title": "Recently Added Movies",
                "Metadata": []
              }
            ]
          }
        }
        """#.utf8)

        let hubs = try JSONDecoder().decode(PlexHubEnvelope.self, from: data).mediaContainer.hubs
        #expect(hubs[0].prefersPosterArtwork)
        #expect(hubs[1].prefersPosterArtwork)
        #expect(!hubs[2].prefersPosterArtwork)
        #expect(hubs[1].metadata[0].posterArtworkPath == "/library/metadata/40/thumb")
    }

    @Test func globalSearchUsesTheAdvertisedEndpointAndPreservesItsQuery() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(#"""
            {
              "MediaContainer": {
                "Hub": [
                  {
                    "hubIdentifier": "show",
                    "title": "Shows",
                    "type": "show",
                    "Directory": [
                      {
                        "key": "/hubs/search?query=simpsons",
                        "title": "Search All Libraries"
                      },
                      {
                        "ratingKey": "100",
                        "key": "/library/metadata/100/children",
                        "title": "The Simpsons",
                        "type": "show",
                        "reason": "section",
                        "reasonTitle": "TV Shows",
                        "reasonID": 2
                      }
                    ]
                  },
                  {
                    "hubIdentifier": "movie",
                    "title": "Movies",
                    "type": "movie",
                    "Metadata": [{
                      "ratingKey": "200",
                      "key": "/library/metadata/200",
                      "title": "The Simpsons Movie",
                      "type": "movie",
                      "reason": "show",
                      "reasonTitle": "The Simpsons",
                      "reasonID": "100"
                    }]
                  },
                  {
                    "hubIdentifier": "empty",
                    "title": "Empty",
                    "Metadata": []
                  }
                ]
              }
            }
            """#.utf8))
        }

        let hubs = try await PlexAPIClient(session: session).fetchSearchHubs(
            query: "  simpsons  ",
            endpointPath: "/provider/search?includeCollections=1&limit=2",
            using: try configuration,
            limit: 8
        )

        let request = try #require(capture.request)
        let components = try #require(
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        )
        #expect(components.path == "/provider/search")
        #expect(components.queryItems == [
            URLQueryItem(name: "includeCollections", value: "1"),
            URLQueryItem(name: "query", value: "simpsons"),
            URLQueryItem(name: "limit", value: "8"),
        ])
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
        #expect(hubs.map(\.title) == ["Shows", "Movies"])
        #expect(hubs[0].metadata.map(\.title) == ["The Simpsons"])
        #expect(hubs[0].metadata[0].reason == "section")
        #expect(hubs[0].metadata[0].reasonTitle == "TV Shows")
        #expect(hubs[0].metadata[0].reasonID == "2")
        #expect(hubs[0].metadata[0].subtitle == "TV Shows · Show")
        #expect(hubs[1].metadata[0].reasonID == "100")
    }

    @MainActor
    @Test func failedHomeRefreshKeepsTheExistingServerFeedVisible() async throws {
        let suiteName = "PlexBarTests.failedHomeRefreshKeepsTheExistingServerFeedVisible"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let session = makeMediaMockSession { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            switch request.url?.path {
            case "/media/providers":
                return (response, libraryProviderData())
            case "/provider/promoted":
                return (response, promotedHubsData())
            default:
                Issue.record("Unexpected request: \(request.url?.absoluteString ?? "nil")")
                return (response, Data(#"{"MediaContainer":{}}"#.utf8))
            }
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
        #expect(store.homeHubs.map(\.title) == ["Recently Added Movies"])

        MediaMockURLProtocol.requestHandler = { _ in
            throw PlexAPIError.invalidResponse
        }
        await store.loadHomeHubs(forceRefresh: true)

        #expect(store.homeHubs.map(\.title) == ["Recently Added Movies"])
        #expect(store.homeHubsErrorMessage != nil)
    }

    @Test func fetchMediaPageUsesPlexPaginationHeadersAndDecodesItems() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Plex-Container-Total-Size": "250"]
            ))
            let data = Data(#"""
            {
              "MediaContainer": {
                "offset": 100,
                "Metadata": [
                  { "ratingKey": "42", "title": "Charade", "type": "movie", "year": 1963, "Media": [] }
                ]
              }
            }
            """#.utf8)
            return (response, data)
        }

        let page = try await PlexAPIClient(session: session).fetchMediaPage(
            libraryID: "1",
            using: try configuration,
            start: 100,
            size: 50
        )

        #expect(page.items.map { $0.title } == ["Charade"])
        #expect(page.offset == 100)
        #expect(page.totalSize == 250)

        let request = try #require(capture.request)
        #expect(request.url?.path == "/library/sections/1/all")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Start") == "100")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "50")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(components.queryItems?.contains { $0.name == "sort" } != true)
    }

    @Test func metadataRequestExplicitlyIncludesCinematicMetadata() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(#"""
            {
              "MediaContainer": {
                "Metadata": [{
                  "ratingKey": "42",
                  "title": "Episode",
                  "type": "episode",
                  "Image": [{
                    "type": "clearLogo",
                    "url": "/library/metadata/40/clearLogo/1700000000",
                    "alt": "Example Show"
                  }],
                  "Marker": [{
                    "id": 7,
                    "type": "intro",
                    "startTimeOffset": 30000,
                    "endTimeOffset": 92000
                  }],
                  "Rating": [{
                    "image": "imdb://image.rating",
                    "type": "audience",
                    "value": 7.8
                  }],
                  "Guid": [{ "id": "imdb://tt1234567" }]
                }]
              }
            }
            """#.utf8))
        }

        let item = try await PlexAPIClient(session: session).fetchMediaMetadata(
            ratingKey: "42",
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try #require(
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        )
        #expect(components.path == "/library/metadata/42")
        #expect(components.queryItems == [
            URLQueryItem(name: "includeOptionalElements", value: "Image,Marker,Rating"),
            URLQueryItem(name: "includeGuids", value: "1"),
        ])
        #expect(item.clearLogoPath == "/library/metadata/40/clearLogo/1700000000")
        #expect(item.images.first?.alt == "Example Show")
        #expect(item.markers.map(\.id) == ["7"])
        #expect(item.ratings.count == 1)
        #expect(item.ratings.first?.image == "imdb://image.rating")
        #expect(item.ratings.first?.type == "audience")
        #expect(item.ratings.first?.value == 7.8)
        #expect(item.guids.map(\.id) == ["imdb://tt1234567"])
    }

    @MainActor
    @Test func mediaRouteResolvesUncachedHistoryMetadataAndRetainsItForNavigation() async throws {
        let suiteName = "PlexBarTests.mediaRouteResolvesUncachedHistoryMetadata"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let session = makeMediaMockSession { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(#"{"MediaContainer":{"Metadata":[{"ratingKey":"900","key":"/library/metadata/900/children","type":"show","title":"Severance"}]}}"#.utf8))
        }
        let credentials = PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(credentials: credentials),
            initialCredentials: credentials
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
        let route = try #require(PlexMediaRoute(ratingKey: "900"))

        #expect(store.item(for: route) == nil)
        let resolvedItem = try await store.resolveItem(for: route)
        #expect(resolvedItem.title == "Severance")
        #expect(store.item(for: route) == resolvedItem)

        MediaMockURLProtocol.requestHandler = { _ in
            throw PlexAPIError.invalidResponse
        }
        #expect(try await store.resolveItem(for: route) == resolvedItem)

        store.resetResolvedMediaItems()
        #expect(store.item(for: route) == nil)
    }

    @Test func playbackDecisionBuildsAuthenticatedDirectPlayURL() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, directPlayDecisionData())
        }

        let item = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: playableItemData()
        )
        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try configuration,
            capabilities: PlexPlaybackCapabilities(
                directPlayContainers: ["mp4"],
                directPlayVideoCodecs: ["h264"],
                directPlayAudioCodecs: ["aac"]
            )
        )

        #expect(plan.method == PlexPlaybackPlan.Method.directPlay)
        #expect(plan.mediaKind == .video)
        #expect(plan.startTime == 5)
        #expect(plan.duration == 60)
        #expect(plan.url.path == "/library/parts/7/file.mp4")

        let playbackComponents = try #require(URLComponents(url: plan.url, resolvingAgainstBaseURL: false))
        let playbackQueryItems = playbackComponents.queryItems ?? []
        let hasToken = playbackQueryItems.contains { item in
            item.name == "X-Plex-Token" && item.value == "server-token"
        }
        let hasSessionIdentifier = playbackQueryItems.contains { item in
            item.name == "X-Plex-Session-Identifier" && item.value == plan.sessionIdentifier
        }
        let hasClientIdentifier = playbackQueryItems.contains { item in
            item.name == "X-Plex-Client-Identifier" && item.value == "client-123"
        }
        #expect(hasToken)
        #expect(hasSessionIdentifier)
        #expect(hasClientIdentifier)

        let decisionRequest = try #require(capture.request)
        #expect(decisionRequest.url?.path == "/video/:/transcode/universal/decision")
        #expect(decisionRequest.value(forHTTPHeaderField: "X-Plex-Session-Identifier") == plan.sessionIdentifier)
        #expect(decisionRequest.value(forHTTPHeaderField: "X-Plex-Client-Profile-Name") == "generic")
        let profile = decisionRequest.value(forHTTPHeaderField: "X-Plex-Client-Profile-Extra")
        #expect(profile?.contains("add-direct-play-profile") == true)
        #expect(profile?.contains("subtitleCodec=*") == true)
    }

    @Test func reportTimelinePostsCanonicalStoppedQueueState() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(#"{"MediaContainer":{}}"#.utf8))
        }

        _ = try await PlexAPIClient(session: session).reportTimeline(
            PlexTimelineUpdate(
                ratingKey: "42",
                state: .stopped,
                time: 12_000,
                duration: 60_000,
                sessionIdentifier: "session-123",
                playQueueItemID: "queue-item-9",
                continuing: true
            ),
            endpointPath: "/provider/timeline?source=library",
            using: try configuration
        )

        let request = try #require(capture.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/provider/timeline")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Session-Identifier") == "session-123")
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(components.queryItems?.contains { $0.name == "source" && $0.value == "library" } == true)
        #expect(components.queryItems?.contains { $0.name == "ratingKey" && $0.value == "42" } == true)
        #expect(components.queryItems?.contains { $0.name == "state" && $0.value == "stopped" } == true)
        #expect(components.queryItems?.contains { $0.name == "time" && $0.value == "12000" } == true)
        #expect(
            components.queryItems?.contains {
                $0.name == "playQueueItemID" && $0.value == "queue-item-9"
            } == true
        )
        #expect(components.queryItems?.contains { $0.name == "continuing" && $0.value == "1" } == true)
        #expect(components.queryItems?.contains { $0.name == "offline" } != true)
    }

    @Test func offlineTimelineExplicitlyIdentifiesDeferredPlayback() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(#"{"MediaContainer":{}}"#.utf8))
        }

        _ = try await PlexAPIClient(session: session).reportTimeline(
            PlexTimelineUpdate(
                ratingKey: "42",
                state: .stopped,
                time: 48_000,
                duration: 60_000,
                sessionIdentifier: "offline-session",
                offline: true
            ),
            endpointPath: "/provider/timeline",
            using: try configuration
        )

        let components = try #require(capture.request?.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(components.queryItems?.contains { $0.name == "offline" && $0.value == "1" } == true)
    }

    @Test func transcodePlanCarriesRequiredPlexContextIntoHLSURL() async throws {
        let session = makeMediaMockSession { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }

        let item = try JSONDecoder().decode(PlexMediaItem.self, from: playableItemData())
        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try configuration,
            capabilities: PlexPlaybackCapabilities(
                directPlayContainers: ["mp4"],
                directPlayVideoCodecs: ["h264"],
                directPlayAudioCodecs: ["aac"]
            )
        )

        #expect(plan.method == .transcode)
        #expect(plan.url.path == "/video/:/transcode/universal/start.m3u8")
        let components = try #require(URLComponents(url: plan.url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        #expect(queryItems.contains { $0.name == "X-Plex-Client-Identifier" && $0.value == "client-123" })
        #expect(queryItems.contains { $0.name == "X-Plex-Client-Profile-Name" && $0.value == "generic" })
        #expect(queryItems.contains { $0.name == "X-Plex-Client-Profile-Extra" })
        #expect(queryItems.contains { $0.name == "X-Plex-Session-Identifier" })
        #expect(queryItems.contains { $0.name == "X-Plex-Token" && $0.value == "server-token" })
    }

    private var configuration: PlexConnectionConfiguration {
        get throws {
            PlexConnectionConfiguration(
                serverURL: try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400")),
                token: "server-token",
                clientContext: PlexClientContext(clientIdentifier: "client-123")
            )
        }
    }
}

private func promotedHubsData() -> Data {
    Data(#"""
    {
      "MediaContainer": {
        "Hub": [{
          "hubIdentifier": "home.movies.recent",
          "hubKey": "/library/metadata/42",
          "key": "/hubs/home/recentlyAdded?type=1",
          "title": "Recently Added Movies",
          "type": "movie",
          "style": "shelf",
          "size": "1",
          "totalSize": 12,
          "more": "1",
          "promoted": true,
          "Metadata": [{
            "ratingKey": "42",
            "key": "/library/metadata/42",
            "title": "Charade",
            "type": "movie",
            "Media": []
          }]
        }]
      }
    }
    """#.utf8)
}

private func libraryProviderData() -> Data {
    Data(#"""
    {
      "MediaContainer": {
        "MediaProvider": [{
          "identifier": "com.plexapp.plugins.library",
          "Feature": [{
            "type": "promoted",
            "key": "/provider/promoted?includeTypeFirst=1"
          }, {
            "type": "search",
            "key": "/provider/search"
          }]
        }]
      }
    }
    """#.utf8)
}

func directPlayDecisionData() -> Data {
    Data(#"""
    {
      "MediaContainer": {
        "generalDecisionCode": "1000",
        "Metadata": [{
          "ratingKey": "42",
          "title": "Charade",
          "Media": [{
            "id": "901",
            "selected": "1",
            "Part": [{
              "id": "902",
              "selected": "1",
              "decision": "directplay",
              "key": "/library/parts/7/file.mp4",
              "Stream": [{ "id": "903", "streamType": "1", "selected": "1" }]
            }]
          }]
        }]
      }
    }
    """#.utf8)
}

func playableItemData() -> Data {
    Data(#"""
    {
      "ratingKey": "42",
      "title": "Charade",
      "duration": 60000,
      "viewOffset": 5000,
      "Media": [{ "Part": [{ "key": "/library/parts/7/file.mp4" }] }]
    }
    """#.utf8)
}

func transcodeDecisionData() -> Data {
    Data(#"""
    {
      "MediaContainer": {
        "generalDecisionCode": "1001",
        "Metadata": [{
          "ratingKey": "42",
          "title": "Charade",
          "Media": [{
            "selected": "1",
            "Part": [{
              "selected": "1",
              "decision": "transcode",
              "Stream": [{ "streamType": "1", "decision": "transcode" }]
            }]
          }]
        }]
      }
    }
    """#.utf8)
}

func makeMediaMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    MediaMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MediaMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

final class MediaMockURLProtocol: URLProtocol, @unchecked Sendable {
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
