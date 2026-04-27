import AppKit
import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexRequestTests {
    @Test func fetchSessionsUsesCanonicalPlexHeaders() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{"MediaContainer":{"Metadata":[]}}"#.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAPIClient(session: session)
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
        let clientContext = PlexClientContext(clientIdentifier: "client-123")

        let sessions = try await client.fetchSessions(using: PlexConnectionConfiguration(
            serverURL: serverURL,
            token: "server-token",
            clientContext: clientContext
        ))

        #expect(sessions.isEmpty)

        let request = try #require(capture.request)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "client-123")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Product") == AppConstants.appName)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Version") == AppConstants.productVersion)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Platform") == "macOS")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Device") == "Mac")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Device-Name") == "Mac (\(AppConstants.appName))")
    }

    @Test func fetchSessionUsesSessionKeyQueryParameter() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{"MediaContainer":{"Metadata":[]}}"#.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAPIClient(session: session)
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
        let clientContext = PlexClientContext(clientIdentifier: "client-123")

        let fetchedSession = try await client.fetchSession(using: PlexConnectionConfiguration(
            serverURL: serverURL,
            token: "server-token",
            clientContext: clientContext
        ), sessionKey: "77")

        #expect(fetchedSession == nil)

        let request = try #require(capture.request)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/status/sessions")
        #expect(components.queryItems?.contains(where: { $0.name == "sessionKey" && $0.value == "77" }) == true)
    }

    @Test func fetchSessionReturnsOnlyTheMatchingSessionKey() async throws {
        let session = makeMockSession { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            {
              "MediaContainer": {
                "Metadata": [
                  {
                    "type": "episode",
                    "sessionKey": "44",
                    "title": "Wrong Session",
                    "Session": { "id": "wrong", "key": "44" },
                    "Player": { "title": "Safari", "product": "Safari", "state": "playing", "platform": "macOS" },
                    "User": { "title": "test-user", "id": "1" },
                    "key": "/library/metadata/900",
                    "ratingKey": "900",
                    "viewOffset": 1000
                  },
                  {
                    "type": "episode",
                    "sessionKey": "77",
                    "title": "Right Session",
                    "Session": { "id": "right", "key": "77" },
                    "Player": { "title": "Safari", "product": "Safari", "state": "playing", "platform": "macOS" },
                    "User": { "title": "test-user", "id": "1" },
                    "key": "/library/metadata/901",
                    "ratingKey": "901",
                    "viewOffset": 2000
                  }
                ]
              }
            }
            """#.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAPIClient(session: session)
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
        let clientContext = PlexClientContext(clientIdentifier: "client-123")

        let fetchedSession = try await client.fetchSession(using: PlexConnectionConfiguration(
            serverURL: serverURL,
            token: "server-token",
            clientContext: clientContext
        ), sessionKey: "77")

        #expect(fetchedSession?.canonicalSessionKey == "77")
        #expect(fetchedSession?.title == "Right Session")
    }

    @Test func fetchStreamLevelsUsesStreamEndpointAndSubsample() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            {
              "MediaContainer": {
                "size": 3,
                "totalSamples": "487535",
                "Level": [
                  { "v": -20.0 },
                  { "v": -19.8 },
                  { "v": -39.9 }
                ]
              }
            }
            """#.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAPIClient(session: session)
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
        let clientContext = PlexClientContext(clientIdentifier: "client-123")

        let levels = try await client.fetchStreamLevels(
            using: PlexConnectionConfiguration(
                serverURL: serverURL,
                token: "server-token",
                clientContext: clientContext
            ),
            streamID: 384686,
            subsample: 96
        )

        #expect(levels == [-20.0, -19.8, -39.9])

        let request = try #require(capture.request)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/library/streams/384686/levels")
        #expect(components.queryItems?.contains(where: { $0.name == "subsample" && $0.value == "96" }) == true)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
    }

    @Test func notificationsWebSocketURLUsesVerifiedPath() async throws {
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400"))
        let configuration = PlexConnectionConfiguration(
            serverURL: serverURL,
            token: "server-token",
            clientContext: PlexClientContext(clientIdentifier: "client-123")
        )

        let websocketURL = try PlexSessionEventsClient.notificationsURL(using: configuration)

        #expect(websocketURL.absoluteString == "wss://plex.local:32400/:/websockets/notifications")
    }

    @Test func notificationsWebSocketURLPreservesConfiguredBasePath() async throws {
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400/plex"))
        let configuration = PlexConnectionConfiguration(
            serverURL: serverURL,
            token: "server-token",
            clientContext: PlexClientContext(clientIdentifier: "client-123")
        )

        let websocketURL = try PlexSessionEventsClient.notificationsURL(using: configuration)

        #expect(websocketURL.absoluteString == "wss://plex.local:32400/plex/:/websockets/notifications")
    }

    @Test func createPinUsesCanonicalHeadersWithoutToken() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{"id":7,"code":"pin-code","authToken":null}"#.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAuthClient(session: session)
        let clientContext = PlexClientContext(clientIdentifier: "client-123")

        let pin = try await client.createPin(clientContext: clientContext)

        #expect(pin.id == 7)
        #expect(pin.code == "pin-code")

        let request = try #require(capture.request)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "client-123")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Version") == AppConstants.productVersion)
    }

    @Test func fetchAuthenticatedUserUsesPlexTvUserEndpoint() async throws {
        let capture = RequestCapture()
        let avatarURL = PlexRemoteService.apiBaseURL.absoluteString + "/users/example/avatar?c=1234567890"
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require("""
            {
              "id": 42,
              "username": "test-user",
              "title": "Test User",
              "email": "test-user@example.com",
              "thumb": "\(avatarURL)",
              "friendlyName": ""
            }
            """.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAuthClient(session: session)
        let authenticatedUser = try await client.fetchAuthenticatedUser(
            userToken: "user-token",
            clientContext: PlexClientContext(clientIdentifier: "client-123")
        )

        #expect(authenticatedUser == PlexAuthenticatedUser(
            id: 42,
            username: "test-user",
            title: "Test User",
            email: "test-user@example.com",
            thumb: avatarURL,
            friendlyName: ""
        ))

        let request = try #require(capture.request)
        #expect(request.httpMethod == "GET")
        #expect(request.url == PlexRemoteService.apiURL(path: "/api/v2/user"))
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "user-token")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "client-123")
    }

    @Test func fetchServersParsesServerResourcesFromXML() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            <MediaContainer size="1">
              <Device name="Test Server"
                      clientIdentifier="server-id"
                      provides="server,player"
                      accessToken="server-token"
                      productVersion="1.2.3-abc">
                <Connection uri="https://10-0-0-2.server-id.plex.direct:32400" local="1" relay="0" />
                <Connection uri="https://203-0-113-10.server-id.plex.direct:32400" local="0" relay="0" />
                <Connection uri="https://203-0-113-20.server-id.plex.direct:8443" local="0" relay="1" />
              </Device>
            </MediaContainer>
            """#.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAuthClient(session: session)
        let servers = try await client.fetchServers(
            userToken: "user-token",
            clientContext: PlexClientContext(clientIdentifier: "client-123")
        )

        #expect(servers.count == 1)
        #expect(servers.first?.id == "server-id")
        #expect(servers.first?.name == "Test Server")
        #expect(servers.first?.accessToken == "server-token")
        #expect(servers.first?.connections.count == 3)
        #expect(servers.first?.connections.map(\.kind) == [.local, .remote, .relay])

        let request = try #require(capture.request)
        #expect(request.url == PlexRemoteService.apiURL(
            path: "/api/resources",
            queryItems: [
                URLQueryItem(name: "includeHttps", value: "1"),
                URLQueryItem(name: "includeRelay", value: "1"),
                URLQueryItem(name: "includeIPv6", value: "1"),
            ]
        ))
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/xml")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "user-token")
    }

    @Test func fetchGeoLocationUsesPlexTvGeoIPEndpoint() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            <?xml version="1.0" encoding="UTF-8"?>
            <MediaContainer size="1">
              <location city="Portland" subdivisions="Oregon" country="United States" code="US" />
            </MediaContainer>
            """#.data(using: .utf8))
            return (response, data)
        }

        let client = PlexGeoIPClient(session: session)
        let geoLocation = try await client.fetchGeoLocation(
            ipAddress: "73.115.85.232",
            userToken: "user-token",
            clientContext: PlexClientContext(clientIdentifier: "client-123")
        )

        #expect(geoLocation == PlexGeoLocation(
            city: "Portland",
            region: "Oregon",
            country: "United States",
            countryCode: "US"
        ))
        #expect(geoLocation?.displayName == "Portland, Oregon")

        let request = try #require(capture.request)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/v2/geoip")
        #expect(components.queryItems?.contains(where: { $0.name == "ip_address" && $0.value == "73.115.85.232" }) == true)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/xml")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "user-token")
    }

    @Test func imageClientUsesHeaderTokenInsteadOfQueryToken() async throws {
        let capture = RequestCapture()
        let imageData = try #require(NSImage(
            systemSymbolName: "person.circle.fill",
            accessibilityDescription: nil
        )?.tiffRepresentation)
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, imageData)
        }

        let client = PlexImageClient(session: session)
        let clientContext = PlexClientContext(clientIdentifier: "client-123")
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
        let imageURL = try #require(PlexURLBuilder.mediaURL(
            serverURL: serverURL,
            path: "/library/metadata/146/thumb/1715112830"
        ))

        let image = await client.fetchImage(
            from: [imageURL],
            token: "server-token",
            clientContext: clientContext
        )

        #expect(image != nil)

        let request = try #require(capture.request)
        let queryItems = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(queryItems.contains(where: { $0.name == "X-Plex-Token" }) == false)
        #expect(request.value(forHTTPHeaderField: "Accept") == "image/*")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "client-123")
    }

    @Test func imageClientReturnsCachedImageWithoutRepeatingNetworkRequest() async throws {
        let capture = RequestCapture()
        let cache = PlexImageMemoryCache.shared
        let requestCounter = RequestCounter()
        let imageData = try #require(NSImage(
            systemSymbolName: "person.circle.fill",
            accessibilityDescription: nil
        )?.tiffRepresentation)

        let session = makeMockSession { request in
            requestCounter.increment()
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, imageData)
        }

        let client = PlexImageClient(session: session, cache: cache)
        let clientContext = PlexClientContext(clientIdentifier: "client-123")
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
        let imageURL = try #require(PlexURLBuilder.mediaURL(
            serverURL: serverURL,
            path: "/library/metadata/999/thumb/1"
        ))

        let firstImage = await client.fetchImage(
            from: [imageURL],
            token: "server-token",
            clientContext: clientContext
        )
        let secondImage = await client.fetchImage(
            from: [imageURL],
            token: "server-token",
            clientContext: clientContext
        )

        #expect(firstImage != nil)
        #expect(secondImage != nil)
        #expect(requestCounter.value == 1)
    }

    @Test func fetchHistoryUsesThirtyDayCutoffAndPaginationHeaders() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{"MediaContainer":{"Metadata":[]}}"#.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAPIClient(session: session)
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
        let clientContext = PlexClientContext(clientIdentifier: "client-123")
        let cutoffDate = Date(timeIntervalSince1970: 1_700_000_000)

        let history = try await client.fetchHistory(using: PlexConnectionConfiguration(
            serverURL: serverURL,
            token: "server-token",
            clientContext: clientContext
        ), since: cutoffDate, pageSize: 80)

        #expect(history.isEmpty)

        let request = try #require(capture.request)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))

        #expect(components.path == "/status/sessions/history/all")
        #expect(components.queryItems?.contains(where: { $0.name == "sort" && $0.value == "viewedAt:desc" }) == true)
        #expect(components.queryItems?.contains(where: { $0.name == "viewedAt>" && $0.value == "1700000000" }) == true)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Start") == "0")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "80")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
    }

    @Test func fetchAccountsUsesStatisticsMediaEndpoint() async throws {
        let capture = RequestCapture()
        let avatarURL = PlexRemoteService.apiBaseURL.absoluteString + "/users/avatar"
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require("""
            {"MediaContainer":{"Account":[{"id":7,"name":"test-user","thumb":"\(avatarURL)"}]}}
            """.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAPIClient(session: session)
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
        let clientContext = PlexClientContext(clientIdentifier: "client-123")

        let accounts = try await client.fetchAccounts(using: PlexConnectionConfiguration(
            serverURL: serverURL,
            token: "server-token",
            clientContext: clientContext
        ))

        #expect(accounts == [PlexAccount(id: 7, name: "test-user", thumb: avatarURL)])

        let request = try #require(capture.request)
        #expect(request.url?.path == "/statistics/media")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
    }

    @Test func fetchMetadataItemsUsesMetadataEndpoint() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            {
              "MediaContainer": {
                "Metadata": [
                  {
                    "ratingKey": "150",
                    "type": "episode",
                    "grandparentRatingKey": "148",
                    "grandparentTitle": "Babylon 5",
                    "grandparentThumb": "/library/metadata/148/thumb/1715112830"
                  }
                ]
              }
            }
            """#.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAPIClient(session: session)
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
        let clientContext = PlexClientContext(clientIdentifier: "client-123")

        let metadataItems = try await client.fetchMetadataItems(
            using: PlexConnectionConfiguration(
                serverURL: serverURL,
                token: "server-token",
                clientContext: clientContext
            ),
            ids: ["150", "151"]
        )

        #expect(metadataItems == [
            PlexMetadataItem(
                ratingKey: "150",
                grandparentRatingKey: "148",
                grandparentTitle: "Babylon 5",
                grandparentThumb: "/library/metadata/148/thumb/1715112830"
            )
        ])

        let request = try #require(capture.request)
        #expect(request.url?.path == "/library/metadata/150,151")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
    }

    @Test func fetchHistorySeriesIdentitiesThrowsWhenSeriesMetadataIsMissing() async throws {
        let session = makeMockSession { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            {
              "MediaContainer": {
                "Metadata": [
                  {
                    "ratingKey": "150",
                    "grandparentTitle": "Babylon 5"
                  }
                ]
              }
            }
            """#.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAPIClient(session: session)
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
        let clientContext = PlexClientContext(clientIdentifier: "client-123")

        await #expect(throws: PlexAPIError.self) {
            try await client.fetchHistorySeriesIdentities(
                using: PlexConnectionConfiguration(
                    serverURL: serverURL,
                    token: "server-token",
                    clientContext: clientContext
                ),
                episodeIDs: ["150"]
            )
        }
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.requestHandler = handler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
