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
        let session = makeMockSession { request in
            capture.record(request)

            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{"MediaContainer":{"Account":[{"id":7,"name":"smitty_","thumb":"https://plex.tv/users/avatar"}]}}"#.data(using: .utf8))
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

        #expect(accounts == [PlexAccount(id: 7, name: "smitty_", thumb: "https://plex.tv/users/avatar")])

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
