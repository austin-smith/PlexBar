import Foundation
import Testing
@testable import PlexBar

@MainActor
@Test func preservesHistoryWhenAccountFetchFails() async throws {
    let suiteName = "PlexBarTests.preservesHistoryWhenAccountFetchFails"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    settings.serverURLString = "http://plex.local:32400"
    settings.serverToken = "server-token"

    let session = makeMockSession { request in
        let url = try #require(request.url)

        if url.path == "/status/sessions/history/all" {
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            {
              "MediaContainer": {
                "Metadata": [
                  {
                    "historyKey": "/status/sessions/history/9",
                    "key": "/library/metadata/500",
                    "ratingKey": "500",
                    "title": "Bob's Burgers",
                    "type": "episode",
                    "grandparentTitle": "Bob's Burgers",
                    "viewedAt": 1712452410,
                    "accountID": 42
                  }
                ]
              }
            }
            """#.data(using: .utf8))
            return (response, data)
        }

        if url.path == "/library/metadata/500" {
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            {
              "MediaContainer": {
                "Metadata": [
                  {
                    "ratingKey": "500",
                    "type": "episode",
                    "grandparentRatingKey": "900",
                    "grandparentTitle": "Bob's Burgers",
                    "grandparentThumb": "/library/metadata/900/thumb/1715112830"
                  }
                ]
              }
            }
            """#.data(using: .utf8))
            return (response, data)
        }

        if url.path == "/statistics/media" {
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        throw URLError(.unsupportedURL)
    }

    let store = PlexHistoryStore(
        settings: settings,
        client: PlexAPIClient(session: session)
    )

    store.refreshNow()
    await waitForHistoryRefresh(on: store)

    #expect(store.recentItems.count == 1)
    #expect(store.recentItems.first?.title == "Bob's Burgers")
    #expect(store.accountsByID.isEmpty)
    #expect(store.errorMessage == nil)
    #expect(store.lastUpdated != nil)
}

@MainActor
private func waitForHistoryRefresh(
    on store: PlexHistoryStore,
    timeoutNanoseconds: UInt64 = 2_000_000_000
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if !store.isLoading && !store.recentItems.isEmpty {
            return
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

private func makeMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    HistoryStoreMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HistoryStoreMockURLProtocol.self]
    return URLSession(configuration: configuration)
}


private final class HistoryStoreMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
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
