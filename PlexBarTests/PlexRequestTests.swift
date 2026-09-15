import PlexModels
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
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
        #expect(request.value(forHTTPHeaderField: "X-Plex-Pms-Api-Version") == "1.0.0")
    }

    @Test func fetchSessionsReturnsTheCompleteActiveSessionList() async throws {
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

        let fetchedSessions = try await client.fetchSessions(using: PlexConnectionConfiguration(
            serverURL: serverURL,
            token: "server-token",
            clientContext: clientContext
        ))

        #expect(fetchedSessions.map(\.canonicalSessionKey) == ["44", "77"])
        #expect(fetchedSessions.map(\.title) == ["Wrong Session", "Right Session"])
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
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "key-123")
        let jwk = try identity.publicJWK(includeUse: false)

        let pin = try await client.createPin(jwk: jwk, clientContext: clientContext)

        #expect(pin.id == 7)
        #expect(pin.code == "pin-code")

        let request = try #require(capture.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "clients.plex.tv")
        #expect(request.url?.path == "/api/v2/pins")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Pms-Api-Version") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "client-123")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Version") == AppConstants.productVersion)

        let body = try requestBodyData(request)
        #expect(!body.isEmpty)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["strong"] as? Bool == true)
        let encodedJWK = try #require(object["jwk"] as? [String: Any])
        #expect(encodedJWK["kty"] as? String == "OKP")
        #expect(encodedJWK["crv"] as? String == "Ed25519")
        #expect(encodedJWK["alg"] as? String == "EdDSA")
        #expect(encodedJWK["kid"] as? String == "key-123")
        #expect(encodedJWK["x"] as? String == jwk.x)
        #expect(encodedJWK["use"] == nil)
    }

    @Test func createPinCanRequestTelevisionLinkCode() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{"id":8,"code":"ABCD","authToken":null}"#.data(using: .utf8))
            return (response, data)
        }
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "key-tv")

        _ = try await PlexAuthClient(session: session).createPin(
            jwk: identity.publicJWK(includeUse: false),
            strong: false,
            clientContext: PlexClientContext(clientIdentifier: "tv-client")
        )

        let request = try #require(capture.request)
        let body = try requestBodyData(request)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["strong"] as? Bool == false)
        #expect((object["jwk"] as? [String: Any])?["kid"] as? String == "key-tv")
    }

    @Test func fetchPinSendsDeviceJWTAsQueryParameter() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{"id":7,"code":"pin-code","authToken":"account-jwt"}"#.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAuthClient(session: session)
        let pin = try await client.fetchPin(
            id: "7",
            deviceJWT: "signed.device.jwt",
            clientContext: PlexClientContext(clientIdentifier: "client-123")
        )

        #expect(pin.authToken == "account-jwt")
        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(request.httpMethod == "GET")
        #expect(components.host == "clients.plex.tv")
        #expect(components.path == "/api/v2/pins/7")
        #expect(components.queryItems == [URLQueryItem(name: "deviceJWT", value: "signed.device.jwt")])
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == nil)
    }

    @Test func registerJWKUsesLegacyTokenAndSignatureUse() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "key-123")
        let client = PlexAuthClient(session: session)

        try await client.registerJWK(
            identity.publicJWK(includeUse: true),
            legacyToken: "legacy-token",
            clientContext: PlexClientContext(clientIdentifier: "client-123")
        )

        let request = try #require(capture.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url == PlexRemoteService.clientsURL(path: "/api/v2/auth/jwk"))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "legacy-token")
        let body = try requestBodyData(request)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let jwk = try #require(object["jwk"] as? [String: Any])
        #expect(jwk["kid"] as? String == "key-123")
        #expect(jwk["use"] as? String == "sig")
    }

    @Test func fetchJWTNonceUsesCanonicalEndpointWithoutAccountToken() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{"nonce":"plex-nonce"}"#.data(using: .utf8))
            return (response, data)
        }
        let client = PlexAuthClient(session: session)

        let nonce = try await client.fetchJWTNonce(
            clientContext: PlexClientContext(clientIdentifier: "client-123")
        )

        #expect(nonce == "plex-nonce")
        let request = try #require(capture.request)
        #expect(request.httpMethod == "GET")
        #expect(request.url == PlexRemoteService.clientsURL(path: "/api/v2/auth/nonce"))
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == nil)
    }

    @Test func exchangeDeviceJWTSendsSignedJWTInJSONBody() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{"auth_token":"account-jwt"}"#.data(using: .utf8))
            return (response, data)
        }
        let client = PlexAuthClient(session: session)

        let token = try await client.exchangeDeviceJWT(
            "signed.device.jwt",
            clientContext: PlexClientContext(clientIdentifier: "client-123")
        )

        #expect(token == "account-jwt")
        let request = try #require(capture.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url == PlexRemoteService.clientsURL(path: "/api/v2/auth/token"))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == nil)
        let body = try requestBodyData(request)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["jwt"] as? String == "signed.device.jwt")
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
              "friendlyName": "",
              "subscriptions": {
                "subscription": [{
                  "type": "plexpass",
                  "state": "active",
                  "mode": "recurring",
                  "active": true,
                  "subscribedAt": "2026-08-01T00:00:00Z"
                }]
              }
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
            friendlyName: "",
            subscriptions: [PlexUserSubscription(
                type: "plexpass",
                state: "active",
                mode: "recurring",
                active: true,
                subscribedAt: "2026-08-01T00:00:00Z"
            )]
        ))
        #expect(authenticatedUser.hasDownloadsAccountEntitlement)

        let request = try #require(capture.request)
        #expect(request.httpMethod == "GET")
        #expect(request.url == PlexRemoteService.apiURL(path: "/api/v2/user"))
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "user-token")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "client-123")
    }

    @Test func fetchServersUsesResourceConnectionsAndLegacyDeviceCredential() async throws {
        let capture = RequestCapture()
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data: Data
            switch request.url?.path {
            case "/api/v2/resources":
                data = try #require(#"""
                [
                  {
                    "name": "Test Server",
                    "clientIdentifier": "server-id",
                    "provides": "server,player",
                    "accessToken": "resource-jwt-that-pms-rejects",
                    "productVersion": "1.2.3-abc",
                    "connections": [
                      { "uri": "https://10-0-0-2.server-id.plex.direct:32400", "local": true, "relay": false },
                      { "uri": "https://203-0-113-10.server-id.plex.direct:32400", "local": false, "relay": false },
                      { "uri": "https://203-0-113-20.server-id.plex.direct:8443", "local": false, "relay": true }
                    ]
                  }
                ]
                """#.data(using: .utf8))
            case "/api/v2/devices":
                data = try #require(#"""
                [
                  {
                    "name": "Test Server",
                    "clientIdentifier": "server-id",
                    "provides": "server",
                    "token": "legacy-pms-token",
                    "connections": [
                      { "uri": "https://10-0-0-2.server-id.plex.direct:32400" }
                    ]
                  }
                ]
                """#.data(using: .utf8))
            default:
                Issue.record("Unexpected request: \(request)")
                throw URLError(.unsupportedURL)
            }
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
        #expect(servers.first?.accessToken == "legacy-pms-token")
        #expect(servers.first?.connections.count == 3)
        #expect(servers.first?.connections.map(\.kind) == [.local, .remote, .relay])

        #expect(capture.requests.map(\.url) == [
            PlexRemoteService.clientsURL(
                path: "/api/v2/resources",
                queryItems: [
                    URLQueryItem(name: "includeHttps", value: "1"),
                    URLQueryItem(name: "includeRelay", value: "1"),
                    URLQueryItem(name: "includeIPv6", value: "1"),
                ]
            ),
            PlexRemoteService.clientsURL(path: "/api/v2/devices")
        ])
        for request in capture.requests {
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "user-token")
        }
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

    @Test(arguments: [false, true])
    func imageClientRejectsMissingAndInvalidLocalFiles(fileExists: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "plex-image-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        if fileExists { try Data("not an image".utf8).write(to: url) }
        let session = makeMockSession { _ in
            Issue.record("Local image reads must not use the HTTP transport")
            throw URLError(.unsupportedURL)
        }
        let client = PlexImageClient(session: session, cache: PlexImageMemoryCache(), requestCoordinator: PlexImageRequestCoordinator())

        #expect(await client.fetchCGImageResult(
            from: [url], token: "", clientContext: PlexClientContext(clientIdentifier: "tests")
        ) == nil)
    }

    @Test func imageClientRejectsHTTPFailureWithValidImageBody() async throws {
        let imageData = try #require(makeArtworkData(width: 40, height: 40))
        let session = makeMockSession { request in
            let response = try #require(HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil))
            return (response, imageData)
        }
        let client = PlexImageClient(session: session, cache: PlexImageMemoryCache(), requestCoordinator: PlexImageRequestCoordinator())
        let url = try #require(URL(string: "https://plex.local/forbidden-image"))

        #expect(await client.fetchCGImageResult(
            from: [url], token: "", clientContext: PlexClientContext(clientIdentifier: "tests")
        ) == nil)
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

    @Test func publicImageRequestsDoNotDisclosePlexDeviceHeaders() async throws {
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
        let client = PlexImageClient(
            session: session,
            cache: PlexImageMemoryCache(),
            requestCoordinator: PlexImageRequestCoordinator()
        )
        let imageURL = try #require(URL(string: "https://metadata-static.plex.tv/person.jpg"))

        let image = await client.fetchImage(
            from: [imageURL],
            token: "",
            clientContext: PlexClientContext(clientIdentifier: "stable-device-identifier")
        )

        #expect(image != nil)
        let request = try #require(capture.request)
        #expect(request.value(forHTTPHeaderField: "Accept") == "image/*")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Product") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Platform") == nil)
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

    @Test func imageClientCoalescesConcurrentAuthenticatedArtworkRequests() async throws {
        let requestCounter = RequestCounter()
        let imageData = try #require(makeArtworkData(width: 320, height: 480))
        let session = makeMockSession { request in
            requestCounter.increment()
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, imageData)
        }
        let client = PlexImageClient(
            session: session,
            cache: PlexImageMemoryCache(),
            requestCoordinator: PlexImageRequestCoordinator()
        )
        let clientContext = PlexClientContext(clientIdentifier: "coalescing-client")
        let imageURL = try #require(URL(string: "https://plex.local/library/metadata/coalesced/thumb"))

        async let firstImage = client.fetchCGImageResult(
            from: [imageURL],
            token: "server-token",
            clientContext: clientContext,
            maximumPixelSize: 240
        )
        async let secondImage = client.fetchCGImageResult(
            from: [imageURL],
            token: "server-token",
            clientContext: clientContext,
            maximumPixelSize: 240
        )
        let images = await (firstImage, secondImage)

        #expect(images.0 != nil)
        #expect(images.1 != nil)
        #expect(requestCounter.value == 1)
    }

    @Test func imageClientDownsamplesAndSeparatesCacheEntriesByPixelSize() async throws {
        let requestCounter = RequestCounter()
        let imageData = try #require(makeArtworkData(width: 400, height: 200))
        let session = makeMockSession { request in
            requestCounter.increment()
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, imageData)
        }
        let client = PlexImageClient(
            session: session,
            cache: PlexImageMemoryCache(),
            requestCoordinator: PlexImageRequestCoordinator()
        )
        let clientContext = PlexClientContext(clientIdentifier: "downsample-client")
        let imageURL = try #require(URL(string: "https://plex.local/library/metadata/sized/thumb"))

        let small = await client.fetchCGImageResult(
            from: [imageURL],
            token: "server-token",
            clientContext: clientContext,
            maximumPixelSize: 80
        )
        let large = await client.fetchCGImageResult(
            from: [imageURL],
            token: "server-token",
            clientContext: clientContext,
            maximumPixelSize: 160
        )
        let cachedSmall = await client.fetchCGImageResult(
            from: [imageURL],
            token: "server-token",
            clientContext: clientContext,
            maximumPixelSize: 80
        )

        #expect(small?.image.width == 80)
        #expect(small?.image.height == 40)
        #expect(large?.image.width == 160)
        #expect(large?.image.height == 80)
        #expect(cachedSmall?.image.width == 80)
        #expect(requestCounter.value == 2)
    }

    @Test func artworkPrefetcherDeduplicatesWorkWithVisibleArtworkLoading() async throws {
        let requestCounter = RequestCounter()
        let imageData = try #require(makeArtworkData(width: 240, height: 360))
        let session = makeMockSession { request in
            requestCounter.increment()
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, imageData)
        }
        let client = PlexImageClient(
            session: session,
            cache: PlexImageMemoryCache(),
            requestCoordinator: PlexImageRequestCoordinator()
        )
        let prefetcher = PlexArtworkPrefetcher(
            imageClient: client,
            maximumConcurrentRequests: 2,
            maximumQueuedRequests: 4
        )
        let imageURL = try #require(URL(string: "https://plex.local/library/metadata/prefetched/thumb"))
        let request = PlexArtworkPrefetchRequest(
            candidateURLs: [imageURL],
            token: "server-token",
            clientContext: PlexClientContext(clientIdentifier: "prefetch-client"),
            maximumPixelSize: 180
        )

        await prefetcher.prefetch([request, request])
        let visibleImage = await client.fetchCGImageResult(
            from: request.candidateURLs,
            token: request.token,
            clientContext: request.clientContext,
            maximumPixelSize: request.maximumPixelSize
        )

        #expect(visibleImage != nil)
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

    @Test func fetchHistoryCanUsePlexMetadataHierarchyScoping() async throws {
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

        _ = try await client.fetchHistory(
            using: PlexConnectionConfiguration(
                serverURL: serverURL,
                token: "server-token",
                clientContext: PlexClientContext(clientIdentifier: "client-123")
            ),
            since: Date(timeIntervalSince1970: 1_700_000_000),
            metadataItemID: 42,
            pageSize: 50
        )

        let request = try #require(capture.request)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.contains {
            $0.name == "metadataItemID" && $0.value == "42"
        } == true)
        #expect(components.queryItems?.contains {
            $0.name == "viewedAt>" && $0.value == "1700000000"
        } == true)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "50")
    }

    @Test func fetchHistoryIdentityDirectoryUsesStatisticsMediaEndpoint() async throws {
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
            {"MediaContainer":{"Account":[{"id":7,"name":"test-user","thumb":"\(avatarURL)"}],"Device":[{"id":12,"name":"Living Room","platform":"tvOS"}]}}
            """.data(using: .utf8))
            return (response, data)
        }

        let client = PlexAPIClient(session: session)
        let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
        let clientContext = PlexClientContext(clientIdentifier: "client-123")

        let directory = try await client.fetchHistoryIdentityDirectory(using: PlexConnectionConfiguration(
            serverURL: serverURL,
            token: "server-token",
            clientContext: clientContext
        ))

        #expect(directory.accounts == [PlexAccount(id: 7, name: "test-user", thumb: avatarURL)])
        #expect(directory.devices == [PlexHistoryDevice(id: 12, name: "Living Room", platform: "tvOS")])

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

private func makeArtworkData(width: Int, height: Int) -> Data? {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    context.setFillColor(red: 0.18, green: 0.42, blue: 0.76, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else {
        return nil
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        return nil
    }
    return data as Data
}
