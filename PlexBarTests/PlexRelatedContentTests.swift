@testable import PlexClientKit
import PlexModels
import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexRelatedContentTests {
    @Test func requestUsesDocumentedMetadataRelatedEndpointAndDecodesNonemptyHubs() async throws {
        let capture = RequestCapture()
        let session = makeRelatedContentMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.relatedHubsData(ratingKey: "42"))
        }

        let hubs = try await PlexAPIClient(session: session).fetchRelatedHubs(
            ratingKey: "42",
            using: try configuration
        )

        let request = try #require(capture.request)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/hubs/metadata/42/related")
        #expect(request.url?.query == "count=12")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
        #expect(hubs.map(\.title) == ["Related Movies"])
        #expect(hubs.first?.metadata.map(\.title) == ["Related to 42"])
    }

    @Test func postPlayUsesDocumentedEndpointAndPreservesServerHubOrdering() async throws {
        let capture = RequestCapture()
        let session = makeRelatedContentMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (
                response,
                Data(#"{"MediaContainer":{"Hub":[{"hubIdentifier":"postplay.next","title":"Up Next","Metadata":[{"ratingKey":"43","type":"episode","title":"Episode 2"}]},{"hubIdentifier":"postplay.empty","title":"Empty","Metadata":[]},{"hubIdentifier":"postplay.related","title":"Related","Metadata":[{"ratingKey":"44","type":"movie","title":"Another Movie"}]}]}}"#.utf8)
            )
        }

        let hubs = try await PlexAPIClient(session: session).fetchPostPlayHubs(
            ratingKey: "42",
            using: try configuration,
            count: 8
        )

        let request = try #require(capture.request)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/hubs/metadata/42/postplay")
        #expect(request.url?.query == "count=8")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
        #expect(hubs.map(\.title) == ["Up Next", "Related"])
        #expect(hubs.flatMap(\.metadata).map(\.ratingKey) == ["43", "44"])
    }

    @Test func postPlayRejectsNonPMSMetadataIdentityBeforeSendingARequest() async throws {
        let capture = RequestCapture()
        let session = makeRelatedContentMockSession { request in
            capture.record(request)
            throw URLError(.unsupportedURL)
        }

        await #expect(throws: PlexAPIError.self) {
            try await PlexAPIClient(session: session).fetchPostPlayHubs(
                ratingKey: "provider-item",
                using: try configuration
            )
        }
        #expect(capture.request == nil)
    }

    @MainActor
    @Test func failedRefreshKeepsExistingRelatedShelvesVisible() async throws {
        let scenario = RelatedContentScenario()
        let suiteName = "PlexBarTests.failedRelatedContentRefresh"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(defaults: defaults, scenario: scenario)
        let item = try decodeItem(ratingKey: "42")

        await store.loadRelatedContent(for: item)
        #expect(store.relatedHubs(for: item).first?.metadata.map(\.title) == ["Related to 42"])
        #expect(store.relatedContentErrorMessage(for: item) == nil)

        scenario.failRequests(for: "42")
        await store.loadRelatedContent(for: item, forceRefresh: true)

        #expect(store.relatedHubs(for: item).first?.metadata.map(\.title) == ["Related to 42"])
        #expect(store.relatedContentErrorMessage(for: item) != nil)
        #expect(store.hasLoadedRelatedContent(for: item))
    }

    @MainActor
    @Test func relatedContentCacheIsLeastRecentlyUsedAndRouteResolvable() async throws {
        let scenario = RelatedContentScenario()
        let suiteName = "PlexBarTests.relatedContentCacheIsBounded"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(
            defaults: defaults,
            scenario: scenario,
            relatedContentLimit: 2
        )
        let first = try decodeItem(ratingKey: "1")
        let second = try decodeItem(ratingKey: "2")
        let third = try decodeItem(ratingKey: "3")

        await store.loadRelatedContent(for: first)
        await store.loadRelatedContent(for: second)
        let firstHub = try #require(store.relatedHubs(for: first).first)
        let firstRoute = try #require(PlexRelatedHubRoute(sourceItem: first, hub: firstHub))
        await store.loadRelatedHubItems(for: firstRoute)
        await store.loadRelatedContent(for: third)

        #expect(store.hasLoadedRelatedContent(for: first))
        #expect(!store.hasLoadedRelatedContent(for: second))
        #expect(store.hasLoadedRelatedContent(for: third))
        #expect(store.relatedContentState.recency == ["1", "3"])

        let relatedItem = try #require(store.relatedHubItems(for: firstRoute).first)
        #expect(store.item(for: PlexMediaRoute(item: relatedItem)) == relatedItem)

        store.resetRelatedContent()
        #expect(store.relatedContentState.recency.isEmpty)
        #expect(store.relatedHubs(for: first).isEmpty)
        #expect(store.item(for: PlexMediaRoute(item: relatedItem)) == nil)
    }

    @MainActor
    @Test func relatedShowAllFollowsTheExactReturnedKeyAndPaginates() async throws {
        let scenario = RelatedContentScenario()
        let suiteName = "PlexBarTests.relatedShowAllPagination"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(defaults: defaults, scenario: scenario, pageSize: 2)
        let item = try decodeItem(ratingKey: "42")

        await store.loadRelatedContent(for: item)
        let hub = try #require(store.relatedHubs(for: item).first)
        let route = try #require(PlexRelatedHubRoute(sourceItem: item, hub: hub))
        #expect(route.hubKey == "/library/sections/1/all?type=1&relatedTo=42")
        #expect(store.relatedHub(for: route) == hub)

        await store.loadRelatedHubItems(for: route)
        let lastItem = try #require(store.relatedHubItems(for: route).last)
        await store.loadMoreRelatedHubItemsIfNeeded(for: route, currentItem: lastItem)

        #expect(store.relatedHubItems(for: route).map(\.title) == [
            "Related Page 1 for 42",
            "Related Page 2 for 42",
            "Related Page 3 for 42"
        ])
        #expect(!store.hasMoreRelatedHubItems(for: route))

        let requests = scenario.capturedPageRequests()
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.path == "/library/sections/1/all" })
        #expect(requests.allSatisfy { request in
            guard let components = request.url.flatMap({
                URLComponents(url: $0, resolvingAgainstBaseURL: false)
            }) else {
                return false
            }
            return components.queryItems == [
                URLQueryItem(name: "type", value: "1"),
                URLQueryItem(name: "relatedTo", value: "42")
            ]
        })
        #expect(requests.map { $0.value(forHTTPHeaderField: "X-Plex-Container-Start") } == ["0", "2"])
        #expect(requests.map { $0.value(forHTTPHeaderField: "X-Plex-Container-Size") } == ["2", "2"])
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "X-Plex-Token") == "server-token"
        })

        let pagedItem = try #require(store.relatedHubItems(for: route).last)
        #expect(store.item(for: PlexMediaRoute(item: pagedItem)) == pagedItem)
    }

    @MainActor
    @Test func failedRelatedShowAllRefreshKeepsExistingItemsVisible() async throws {
        let scenario = RelatedContentScenario()
        let suiteName = "PlexBarTests.failedRelatedShowAllRefresh"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(defaults: defaults, scenario: scenario, pageSize: 2)
        let item = try decodeItem(ratingKey: "42")

        await store.loadRelatedContent(for: item)
        let hub = try #require(store.relatedHubs(for: item).first)
        let route = try #require(PlexRelatedHubRoute(sourceItem: item, hub: hub))
        await store.loadRelatedHubItems(for: route)

        scenario.failPageRequests()
        await store.loadRelatedHubItems(for: route, forceRefresh: true)

        #expect(store.relatedHubItems(for: route).map(\.title) == [
            "Related Page 1 for 42",
            "Related Page 2 for 42"
        ])
        #expect(store.relatedHubItemsErrorMessage(for: route) != nil)
    }

    @MainActor
    @Test func relatedCacheEvictionRemovesExpandedPagesAndRoutes() async throws {
        let scenario = RelatedContentScenario()
        let suiteName = "PlexBarTests.relatedExpandedCacheEviction"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(
            defaults: defaults,
            scenario: scenario,
            relatedContentLimit: 2,
            pageSize: 2
        )
        let first = try decodeItem(ratingKey: "1")
        let second = try decodeItem(ratingKey: "2")
        let third = try decodeItem(ratingKey: "3")

        await store.loadRelatedContent(for: first)
        let firstHub = try #require(store.relatedHubs(for: first).first)
        let firstRoute = try #require(PlexRelatedHubRoute(sourceItem: first, hub: firstHub))
        await store.loadRelatedHubItems(for: firstRoute)
        let expandedItem = try #require(store.relatedHubItems(for: firstRoute).first)

        await store.loadRelatedContent(for: second)
        await store.loadRelatedContent(for: third)

        #expect(store.relatedHub(for: firstRoute) == nil)
        #expect(store.relatedHubItems(for: firstRoute).isEmpty)
        #expect(store.relatedContentState.itemsByHubRoute[firstRoute] == nil)
        #expect(store.item(for: PlexMediaRoute(item: expandedItem)) == nil)
    }

    @MainActor
    @Test func serverConfirmedMutationsUpdateExpandedRelatedResults() async throws {
        let scenario = RelatedContentScenario()
        let suiteName = "PlexBarTests.relatedExpandedMutationPropagation"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(defaults: defaults, scenario: scenario, pageSize: 2)
        let item = try decodeItem(ratingKey: "42")

        await store.loadRelatedContent(for: item)
        let hub = try #require(store.relatedHubs(for: item).first)
        let route = try #require(PlexRelatedHubRoute(sourceItem: item, hub: hub))
        await store.loadRelatedHubItems(for: route)

        let refreshed = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"page-42-1","type":"movie","title":"Related Page 1 for 42","viewCount":1,"userRating":9}"#.utf8)
        )
        store.replaceCachedRelatedWatchedState(with: refreshed)
        store.replaceCachedRelatedUserRating(with: refreshed)

        let updated = try #require(store.relatedHubItems(for: route).first)
        #expect(updated.isWatched)
        #expect(updated.userRating == 9)
    }

    @MainActor
    @Test func stalePageResponseCannotRepopulateAResetAndReloadedRelatedRoute() async throws {
        let scenario = RelatedContentScenario()
        let suiteName = "PlexBarTests.staleRelatedPageResponse"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(defaults: defaults, scenario: scenario, pageSize: 2)
        let item = try decodeItem(ratingKey: "42")
        await store.loadRelatedContent(for: item)
        let originalHub = try #require(store.relatedHubs(for: item).first)
        let originalRoute = try #require(PlexRelatedHubRoute(sourceItem: item, hub: originalHub))
        let gate = RelatedPageLoadGate()
        let stalePage = PlexMediaPage(
            items: [try decodeItem(ratingKey: "stale")],
            offset: 0,
            totalSize: 1
        )

        let staleLoad = Task {
            await store.loadRelatedHubItems(for: originalRoute) { path, start in
                #expect(path == originalRoute.hubKey)
                #expect(start == 0)
                await gate.suspendLoad()
                return stalePage
            }
        }
        await gate.waitUntilLoadStarts()

        store.resetRelatedContent()
        await store.loadRelatedContent(for: item)
        let reloadedHub = try #require(store.relatedHubs(for: item).first)
        let reloadedRoute = try #require(PlexRelatedHubRoute(sourceItem: item, hub: reloadedHub))
        #expect(reloadedRoute == originalRoute)

        await gate.finishLoad()
        await staleLoad.value

        #expect(store.relatedContentState.itemsByHubRoute[reloadedRoute] == nil)
        #expect(store.relatedHubItems(for: reloadedRoute).map(\.title) == ["Related to 42"])
    }

    private var configuration: PlexConnectionConfiguration {
        get throws {
            PlexConnectionConfiguration(
                serverURL: try #require(URL(string: "https://plex.local:32400")),
                token: "server-token",
                clientContext: PlexClientContext(clientIdentifier: "client-123")
            )
        }
    }

    @MainActor
    private func makeStore(
        defaults: UserDefaults,
        scenario: RelatedContentScenario,
        relatedContentLimit: Int = 12,
        pageSize: Int = 100
    ) throws -> PlexBrowserStore {
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
        return PlexBrowserStore(
            connectionStore: connectionStore,
            client: PlexAPIClient(session: makeRelatedContentMockSession { request in
                try scenario.response(for: request)
            }),
            pageSize: pageSize,
            relatedContentLimit: relatedContentLimit
        )
    }

    private func decodeItem(ratingKey: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"\#(ratingKey)","type":"movie","title":"Item \#(ratingKey)"}"#.utf8)
        )
    }

    fileprivate static func relatedHubsData(ratingKey: String) -> Data {
        Data(#"""
        {
          "MediaContainer": {
            "Hub": [{
              "hubIdentifier": "related.movies.\#(ratingKey)",
              "key": "/library/sections/1/all?type=1&relatedTo=\#(ratingKey)",
              "title": "Related Movies",
              "type": "movie",
              "style": "shelf",
              "size": 1,
              "totalSize": 3,
              "more": true,
              "Metadata": [{
                "ratingKey": "related-\#(ratingKey)",
                "key": "/library/metadata/related-\#(ratingKey)",
                "type": "movie",
                "title": "Related to \#(ratingKey)"
              }]
            }, {
              "hubIdentifier": "related.empty.\#(ratingKey)",
              "title": "Empty",
              "Metadata": []
            }]
          }
        }
        """#.utf8)
    }

    fileprivate static func relatedPageData(ratingKey: String, start: Int) -> Data {
        let metadata: String
        if start == 0 {
            metadata = #"""
            {"ratingKey":"page-\#(ratingKey)-1","key":"/library/metadata/page-\#(ratingKey)-1","type":"movie","title":"Related Page 1 for \#(ratingKey)","viewCount":0,"userRating":2},
            {"ratingKey":"page-\#(ratingKey)-2","key":"/library/metadata/page-\#(ratingKey)-2","type":"movie","title":"Related Page 2 for \#(ratingKey)"}
            """#
        } else {
            metadata = #"""
            {"ratingKey":"page-\#(ratingKey)-3","key":"/library/metadata/page-\#(ratingKey)-3","type":"movie","title":"Related Page 3 for \#(ratingKey)"}
            """#
        }
        return Data(#"""
        {
          "MediaContainer": {
            "offset": \#(start),
            "totalSize": 3,
            "Metadata": [\#(metadata)]
          }
        }
        """#.utf8)
    }
}

private final class RelatedContentScenario: @unchecked Sendable {
    private let lock = NSLock()
    private var failingRatingKeys: Set<String> = []
    private var shouldFailPageRequests = false
    private var pageRequests: [URLRequest] = []

    func failRequests(for ratingKey: String) {
        lock.lock()
        failingRatingKeys.insert(ratingKey)
        lock.unlock()
    }

    func failPageRequests() {
        lock.lock()
        shouldFailPageRequests = true
        lock.unlock()
    }

    func capturedPageRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return pageRequests
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        if url.path == "/library/sections/1/all" {
            let ratingKey = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "relatedTo" })?
                .value ?? ""
            let start = Int(request.value(forHTTPHeaderField: "X-Plex-Container-Start") ?? "0") ?? 0

            lock.lock()
            pageRequests.append(request)
            let shouldFail = shouldFailPageRequests
            lock.unlock()
            if shouldFail {
                throw PlexAPIError.invalidResponse
            }

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Plex-Container-Total-Size": "3"]
            ))
            return (
                response,
                PlexRelatedContentTests.relatedPageData(ratingKey: ratingKey, start: start)
            )
        }

        let ratingKey = url.pathComponents.dropFirst().dropFirst(2).first ?? ""

        lock.lock()
        let shouldFail = failingRatingKeys.contains(ratingKey)
        lock.unlock()
        if shouldFail {
            throw PlexAPIError.invalidResponse
        }

        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        return (response, PlexRelatedContentTests.relatedHubsData(ratingKey: ratingKey))
    }
}

private actor RelatedPageLoadGate {
    private var hasStarted = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var loadContinuation: CheckedContinuation<Void, Never>?

    func suspendLoad() async {
        hasStarted = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func waitUntilLoadStarts() async {
        guard !hasStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func finishLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }
}

private func makeRelatedContentMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    RelatedContentMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RelatedContentMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class RelatedContentMockURLProtocol: URLProtocol, @unchecked Sendable {
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
