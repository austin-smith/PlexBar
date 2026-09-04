import Foundation
import Testing

@testable import PlexBar

@MainActor
@Suite(.serialized)
struct PlexHistoryStoreTests {
    @Test func mediaHistoryLoadsItsOwnViewerAndDeviceDirectory() async throws {
        let suiteName = "PlexBarTests.mediaHistoryLoadsItsOwnViewerAndDeviceDirectory"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let credentials = PlexStoredCredentials(userToken: "account-token", serverToken: "server-token")
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(credentials: credentials),
            initialCredentials: credentials
        )
        settings.selectedServerIdentifier = "server-id"
        settings.selectedServerName = "Server"
        settings.cachedConnectionURLString = "http://plex.local:32400"
        settings.cachedConnectionKind = .local

        let session = makeMockSession { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))

            switch url.path {
            case "/identity":
                return (
                    response,
                    Data(
                        #"{"MediaContainer":{"claimed":true,"machineIdentifier":"server-id","version":"1.0.0"}}"#
                            .utf8)
                )
            case "/status/sessions/history/all":
                return (
                    response,
                    Data(
                        #"{"MediaContainer":{"Metadata":[{"historyKey":"/status/sessions/history/9","key":"/library/metadata/500","ratingKey":"500","title":"Heat","type":"movie","viewedAt":1712452410,"accountID":7,"deviceID":12}]}}"#
                            .utf8)
                )
            case "/statistics/media":
                return (
                    response,
                    Data(
                        #"{"MediaContainer":{"Account":[{"id":7,"name":"Taylor","thumb":"/accounts/7"}],"Device":[{"id":12,"name":"Living Room","platform":"tvOS"}]}}"#
                            .utf8)
                )
            default:
                Issue.record("Unexpected request: \(request)")
                throw URLError(.unsupportedURL)
            }
        }
        let client = PlexAPIClient(session: session)
        let resolver = PlexConnectionResolver(client: client, probeTimeoutInterval: 0.1)
        let connectionStore = PlexConnectionStore(settings: settings, resolver: resolver)
        let libraryStore = PlexLibraryStore(connectionStore: connectionStore, client: client)
        let store = PlexHistoryStore(
            connectionStore: connectionStore,
            libraryStore: libraryStore,
            client: client,
            startsPolling: false
        )
        let item = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"500","type":"movie","title":"Heat"}"#.utf8)
        )

        await store.loadMediaHistory(for: item)

        #expect(store.mediaHistoryPresentation(for: item)?.items.count == 1)
        #expect(store.accountsByID[7]?.name == "Taylor")
        #expect(store.devicesByID[12]?.displayLine == "Living Room · tvOS")
    }

    @Test func preservesHistoryWhenAccountFetchFails() async throws {
        let suiteName = "PlexBarTests.preservesHistoryWhenAccountFetchFails"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = PlexSettingsStore(
            defaults: defaults,
            keychain: KeychainStore(service: "tests.\(suiteName)")
        )
        settings.selectedServerIdentifier = "server-id"
        settings.selectedServerName = "Server"
        settings.serverToken = "server-token"
        settings.cachedConnectionURLString = "http://plex.local:32400"
        settings.cachedConnectionKind = .local

        let session = makeMockSession { request in
            let url = try #require(request.url)

            if url.path == "/identity" {
                let response = try #require(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    ))
                let data = try #require(
                    #"""
                    {
                      "MediaContainer": {
                        "claimed": true,
                        "machineIdentifier": "server-id",
                        "version": "1.0.0"
                      }
                    }
                    """#.data(using: .utf8))
                return (response, data)
            }

            if url.path == "/status/sessions/history/all" {
                let response = try #require(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    ))
                let data = try #require(
                    #"""
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
                let response = try #require(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    ))
                let data = try #require(
                    #"""
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
                let response = try #require(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 500,
                        httpVersion: nil,
                        headerFields: nil
                    ))
                return (response, Data())
            }

            if url.path == "/library/sections/all" {
                let response = try #require(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    ))
                let data = try #require(
                    #"""
                    {
                      "MediaContainer": {
                        "Directory": []
                      }
                    }
                    """#.data(using: .utf8))
                return (response, data)
            }

            throw URLError(.unsupportedURL)
        }

        let resolver = PlexConnectionResolver(
            client: PlexAPIClient(session: session),
            probeTimeoutInterval: 0.1
        )
        let connectionStore = PlexConnectionStore(
            settings: settings,
            resolver: resolver
        )
        let libraryStore = PlexLibraryStore(
            connectionStore: connectionStore,
            client: PlexAPIClient(session: session)
        )

        let store = PlexHistoryStore(
            connectionStore: connectionStore,
            libraryStore: libraryStore,
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
