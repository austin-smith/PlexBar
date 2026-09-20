@testable import PlexClientKit
import PlexModels
import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexMediaExtrasTests {
    @MainActor
    @Test func anExtraDoesNotRequestItsOwnExtras() async throws {
        let suiteName = "PlexBarTests.extraDoesNotHaveExtras"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(defaults: defaults, scenario: MediaExtrasScenario())
        let clip = try JSONDecoder().decode(PlexMediaItem.self, from: Data(
            #"{"ratingKey":"42","type":"clip","title":"Trailer"}"#.utf8
        ))
        await store.loadMediaExtras(for: clip) { _ in
            Issue.record("An extra must not request the unsupported nested extras endpoint.")
            return []
        }
        #expect(store.mediaExtras(for: clip).isEmpty)
        #expect(store.mediaExtrasErrorMessage(for: clip) == nil)
    }

    @Test func documentedPrimaryExtraKeyProducesOnlyServerSupportedDetailActions() throws {
        let movie = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"42","type":"movie","title":"Heat","primaryExtraKey":"/library/metadata/420"}"#.utf8)
        )
        let track = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"84","type":"track","title":"Song","primaryExtraKey":"/library/metadata/840"}"#.utf8)
        )
        let show = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"126","type":"show","title":"Show","primaryExtraKey":"/library/metadata/1260"}"#.utf8)
        )
        let movieWithoutPrimaryExtra = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"168","type":"movie","title":"Movie"}"#.utf8)
        )

        #expect(movie.primaryExtraKey == "/library/metadata/420")
        #expect(movie.primaryExtraActionTitle == "Trailer")
        #expect(track.primaryExtraActionTitle == "Music Video")
        #expect(show.primaryExtraActionTitle == nil)
        #expect(movieWithoutPrimaryExtra.primaryExtraActionTitle == nil)
    }

    @Test func primaryExtraLookupFollowsTheExactServerReturnedMetadataPath() async throws {
        let capture = RequestCapture()
        let session = makeMediaExtrasMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.extrasData(ratingKey: "42"))
        }

        let extra = try await PlexAPIClient(session: session).fetchMediaMetadata(
            path: "/library/metadata/420?includeFields=thumb%2Ctype",
            using: try configuration
        )

        let request = try #require(capture.request)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/metadata/420")
        #expect(request.url?.query == "includeFields=thumb,type")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
        #expect(extra.title == "Making the Movie")
    }

    @Test func documentedExtraSubtypesHaveHumanReadableLabels() throws {
        let expectedLabels = [
            "trailer": "Trailer",
            "deletedScene": "Deleted Scene",
            "interview": "Interview",
            "musicVideo": "Music Video",
            "behindTheScenes": "Behind the Scenes",
            "sceneOrSample": "Scene or Sample",
            "liveMusicVideo": "Live Music Video",
            "lyricMusicVideo": "Lyric Music Video",
            "concert": "Concert",
            "featurette": "Featurette",
            "short": "Short",
            "other": "Other"
        ]

        for (subtype, expectedLabel) in expectedLabels {
            let data = Data(
                #"{"ratingKey":"\#(subtype)","type":"clip","subtype":"\#(subtype)","title":"Extra"}"#.utf8
            )
            let item = try JSONDecoder().decode(PlexMediaItem.self, from: data)

            #expect(item.extraSubtypeLabel == expectedLabel)
            #expect(item.subtitle == expectedLabel)
        }
    }

    @Test func requestUsesDocumentedMetadataExtrasEndpointAndDecodesClipLabels() async throws {
        let capture = RequestCapture()
        let session = makeMediaExtrasMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.extrasData(ratingKey: "42"))
        }

        let extras = try await PlexAPIClient(session: session).fetchMediaExtras(
            ratingKey: "42",
            using: try configuration
        )

        let request = try #require(capture.request)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/metadata/42/extras")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")

        let extra = try #require(extras.first)
        #expect(extra.title == "Making the Movie")
        #expect(extra.subtype == "behindTheScenes")
        #expect(extra.extraSubtypeLabel == "Behind the Scenes")
        #expect(extra.subtitle == "Behind the Scenes")
        #expect(extra.isPlayable)
    }

    @MainActor
    @Test func failedRefreshKeepsExistingExtrasVisible() async throws {
        let scenario = MediaExtrasScenario()
        let suiteName = "PlexBarTests.failedMediaExtrasRefresh"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(defaults: defaults, scenario: scenario)
        let item = try decodeItem(ratingKey: "42")

        await store.loadMediaExtras(for: item)
        #expect(store.mediaExtras(for: item).map(\.title) == ["Making the Movie"])
        #expect(store.mediaExtrasErrorMessage(for: item) == nil)

        scenario.failRequests(for: "42")
        await store.loadMediaExtras(for: item, forceRefresh: true)

        #expect(store.mediaExtras(for: item).map(\.title) == ["Making the Movie"])
        #expect(store.mediaExtrasErrorMessage(for: item) != nil)
        #expect(store.hasLoadedMediaExtras(for: item))
    }

    @MainActor
    @Test func extrasCacheIsLeastRecentlyUsedRouteResolvableAndResettable() async throws {
        let scenario = MediaExtrasScenario()
        let suiteName = "PlexBarTests.mediaExtrasCacheIsBounded"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(
            defaults: defaults,
            scenario: scenario,
            mediaExtrasLimit: 2
        )
        let first = try decodeItem(ratingKey: "1")
        let second = try decodeItem(ratingKey: "2")
        let third = try decodeItem(ratingKey: "3")

        await store.loadMediaExtras(for: first)
        await store.loadMediaExtras(for: second)
        await store.loadMediaExtras(for: first)
        await store.loadMediaExtras(for: third)

        #expect(store.hasLoadedMediaExtras(for: first))
        #expect(!store.hasLoadedMediaExtras(for: second))
        #expect(store.hasLoadedMediaExtras(for: third))
        #expect(store.mediaExtrasState.recency == ["1", "3"])

        let extra = try #require(store.mediaExtras(for: first).first)
        #expect(store.item(for: PlexMediaRoute(item: extra)) == extra)

        store.resetMediaExtras()
        #expect(store.mediaExtrasState.recency.isEmpty)
        #expect(store.mediaExtras(for: first).isEmpty)
        #expect(store.item(for: PlexMediaRoute(item: extra)) == nil)
    }

    @MainActor
    @Test func detailDiscoveryLoadsAndResetsExtrasAndRelatedContentTogether() async throws {
        let scenario = MediaExtrasScenario()
        let suiteName = "PlexBarTests.detailDiscoveryLoadsBothContracts"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(defaults: defaults, scenario: scenario)
        let item = try decodeItem(ratingKey: "42")

        #expect(!store.detailDiscoveryPresentation(for: item).isVisible)

        await store.loadDetailDiscoveryContent(for: item)

        #expect(store.mediaExtras(for: item).map(\.title) == ["Making the Movie"])
        #expect(store.relatedHubs(for: item).map(\.title) == ["Related Movies"])
        #expect(store.detailDiscoveryPresentation(for: item) == PlexDetailDiscoveryPresentation(
            hasContent: true,
            hasError: false,
            isLoading: false
        ))

        store.resetDetailDiscoveryContent()

        #expect(store.mediaExtras(for: item).isEmpty)
        #expect(store.relatedHubs(for: item).isEmpty)
        #expect(!store.detailDiscoveryPresentation(for: item).isVisible)
    }

    @MainActor
    @Test func staleExtrasResponseCannotRepopulateAResetAndReloadedSource() async throws {
        let scenario = MediaExtrasScenario()
        let suiteName = "PlexBarTests.staleMediaExtrasResponse"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(defaults: defaults, scenario: scenario)
        let item = try decodeItem(ratingKey: "42")
        let staleExtra = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"stale-extra","type":"clip","title":"Stale Extra"}"#.utf8)
        )
        let gate = MediaExtrasLoadGate()

        let staleLoad = Task {
            await store.loadMediaExtras(for: item) { ratingKey in
                #expect(ratingKey == "42")
                await gate.suspendLoad()
                return [staleExtra]
            }
        }
        await gate.waitUntilLoadStarts()

        store.resetMediaExtras()
        await store.loadMediaExtras(for: item)
        await gate.finishLoad()
        await staleLoad.value

        #expect(store.mediaExtras(for: item).map(\.title) == ["Making the Movie"])
        #expect(store.mediaExtrasState.itemsByRatingKey["42"]?.contains(staleExtra) == false)
    }

    @MainActor
    @Test func serverConfirmedMutationsUpdateCachedExtras() async throws {
        let scenario = MediaExtrasScenario()
        let suiteName = "PlexBarTests.mediaExtrasMutationPropagation"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = try makeStore(defaults: defaults, scenario: scenario)
        let item = try decodeItem(ratingKey: "42")
        await store.loadMediaExtras(for: item)

        let refreshed = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"extra-42","type":"clip","title":"Making the Movie","viewCount":1,"userRating":8}"#.utf8)
        )
        store.replaceCachedMediaExtrasWatchedState(with: refreshed)
        store.replaceCachedMediaExtrasUserRating(with: refreshed)

        let updated = try #require(store.mediaExtras(for: item).first)
        #expect(updated.isWatched)
        #expect(updated.userRating == 8)
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
        scenario: MediaExtrasScenario,
        mediaExtrasLimit: Int = 12
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
            client: PlexAPIClient(session: makeMediaExtrasMockSession { request in
                try scenario.response(for: request)
            }),
            mediaExtrasLimit: mediaExtrasLimit
        )
    }

    private func decodeItem(ratingKey: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"\#(ratingKey)","type":"movie","title":"Item \#(ratingKey)"}"#.utf8)
        )
    }

    fileprivate static func extrasData(ratingKey: String) -> Data {
        Data(#"""
        {
          "MediaContainer": {
            "Metadata": [{
              "ratingKey": "extra-\#(ratingKey)",
              "key": "/library/metadata/extra-\#(ratingKey)",
              "type": "clip",
              "subtype": "behindTheScenes",
              "title": "Making the Movie",
              "duration": 121000,
              "thumb": "/library/metadata/extra-\#(ratingKey)/thumb",
              "Media": [{
                "id": 10,
                "container": "mp4",
                "videoCodec": "h264",
                "Part": [{
                  "id": 20,
                  "key": "/library/parts/20/file.mp4",
                  "container": "mp4"
                }]
              }]
            }]
          }
        }
        """#.utf8)
    }

    fileprivate static func relatedHubsData(ratingKey: String) -> Data {
        Data(#"""
        {
          "MediaContainer": {
            "Hub": [{
              "hubIdentifier": "related.movies.\#(ratingKey)",
              "title": "Related Movies",
              "type": "movie",
              "style": "shelf",
              "Metadata": [{
                "ratingKey": "related-\#(ratingKey)",
                "key": "/library/metadata/related-\#(ratingKey)",
                "type": "movie",
                "title": "Related to \#(ratingKey)"
              }]
            }]
          }
        }
        """#.utf8)
    }
}

private final class MediaExtrasScenario: @unchecked Sendable {
    private let lock = NSLock()
    private var failingRatingKeys: Set<String> = []

    func failRequests(for ratingKey: String) {
        lock.lock()
        failingRatingKeys.insert(ratingKey)
        lock.unlock()
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
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
        let data = if url.path.hasSuffix("/related") {
            PlexMediaExtrasTests.relatedHubsData(ratingKey: ratingKey)
        } else {
            PlexMediaExtrasTests.extrasData(ratingKey: ratingKey)
        }
        return (response, data)
    }
}

private actor MediaExtrasLoadGate {
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

private func makeMediaExtrasMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    MediaExtrasMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MediaExtrasMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class MediaExtrasMockURLProtocol: URLProtocol, @unchecked Sendable {
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
