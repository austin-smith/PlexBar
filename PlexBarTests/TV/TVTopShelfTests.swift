import PlexModels
#if os(tvOS)
@testable import PlexTopShelf
@testable import PlexClientKit
import Foundation
import Synchronization
import Testing
import TVServices
import UIKit
@testable import PlexBarTV

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct TVTopShelfTests {
    @Test(arguments: [TVTopShelfRoute.Action.display, .play])
    func routesRoundTripWithoutCredentials(action: TVTopShelfRoute.Action) throws {
        let route = TVTopShelfRoute(action: action, serverIdentifier: "server &+=?雪", ratingKey: "42")
        #expect(TVTopShelfRoute(url: route.url) == route)
        #expect(route.url.host == "topshelf")
        #expect(!route.url.absoluteString.contains("X-Plex-Token"))
    }

    @Test(arguments: [
        "https://topshelf/play?server=s&item=42",
        "plexbar-tv://other/play?server=s&item=42",
        "plexbar-tv://topshelf/delete?server=s&item=42",
        "plexbar-tv://topshelf/play?server=s&item=../42",
        "plexbar-tv://topshelf/play?server=s&item=42%2Fchildren",
        "plexbar-tv://topshelf/play?server=s&item=-1",
        "plexbar-tv://topshelf/play?server=s&item=",
        "plexbar-tv://topshelf/play?server=&item=42",
        "plexbar-tv://topshelf/play?server=s&item=42&item=43",
        "plexbar-tv://topshelf/play?server=s&item=42&token=secret",
        "plexbar-tv://user@topshelf/play?server=s&item=42",
        "plexbar-tv://topshelf:80/play?server=s&item=42",
        "plexbar-tv://topshelf/play?server=s&item=42#fragment"
    ])
    func malformedRoutesAreRejected(value: String) throws {
        #expect(TVTopShelfRoute(url: try #require(URL(string: value))) == nil)
    }

    @Test func selectionUsesDocumentedHubsInPriorityOrderAndDeduplicates() throws {
        let episode = try item(1, type: "episode")
        let hubs = try [
            hub("home.movies.recent", title: "Films récents", items: [episode, item(2)]),
            hub("home.random", title: "Recently Added", items: [item(3)]),
            hub("continueWatching", title: "Continuer", items: [episode]),
            hub("home.television.recent", items: [item(4, type: "show")]),
            hub("home.music.recent", items: [item(5, type: "album")])
        ]
        let selection = TVTopShelfSelection(hubs: hubs)
        #expect(selection.sections.map(\.identifier) == [
            "continueWatching", "home.movies.recent", "home.television.recent", "home.music.recent"
        ])
        #expect(selection.sections.map(\.title).prefix(2) == ["Continuer", "Films récents"])
        #expect(selection.sections.flatMap(\.items).map(\.ratingKey) == ["1", "2", "4", "5"])
        #expect(TVTopShelfSelection.artworkPath(for: episode) == "/series/poster")
        #expect(TVTopShelfSelection.title(for: episode) == "Series — S1 • E2 - Title 1")
    }

    @Test func selectionIsBoundedAndOmitsUnsupportedOrMissingArtwork() throws {
        let items = try (1...15).map { try item($0) }
        let selection = TVTopShelfSelection(hubs: [
            try hub("continueWatching", items: items),
            try hub("home.movies.recent", items: [items[10], item(16, type: "photo"), item(17, artwork: false)])
        ])
        #expect(selection.sections[0].items.count == 10)
        #expect(selection.sections[1].items.map(\.ratingKey) == ["11"])
    }

    @Test func promotedLibraryRecentHubsKeepServerOrderAndExcludeRecentlyReleased() throws {
        let selection = TVTopShelfSelection(hubs: [
            try hub("tv.recentlyadded.2", title: "Recently Added TV", items: [item(1, type: "show")]),
            try hub("movie.recentlyreleased.1", items: [item(2)]),
            try hub("movie.recentlyadded.1", title: "Recently Added Movies", items: [item(3)]),
            try hub("music.recent.added.3", items: [item(4, type: "album")]),
            try hub("movie.recentlyadded.invalid", items: [item(5)]),
            try hub("movie.recentlyadded.4", items: [item(6)])
        ])
        #expect(selection.sections.map(\.identifier) == ["tv.recentlyadded.2", "movie.recentlyadded.1", "music.recent.added.3", "movie.recentlyadded.4"])
        #expect(selection.sections.flatMap(\.items).map(\.ratingKey) == ["1", "3", "4", "6"])
    }

    @Test func nativeContentHasArtworkForBothScalesProgressAndCorrectActions() throws {
        let cache = temporaryCache()
        defer { try? cache.clear() }
        let filename = try cache.storeImage(jpeg())
        let snapshot = snapshot(filename: filename, progress: 0.4)
        try cache.write(snapshot)
        #expect(try cache.read() == snapshot)
        let content = try #require(TVTopShelfContentBuilder.make(snapshot: snapshot, cache: cache))
        #expect(content.sections.count == 1)
        let entry = try #require(content.sections.first?.items.first)
        #expect(entry.title == "Continue this episode")
        #expect(entry.imageShape == .poster)
        #expect(entry.playbackProgress == 0.4)
        #expect(entry.imageURL(for: .screenScale1x) == cache.imageURL(filename: filename))
        #expect(entry.imageURL(for: .screenScale2x) == cache.imageURL(filename: filename))
        #expect(TVTopShelfRoute(url: try #require(entry.displayAction?.url))?.action == .display)
        #expect(TVTopShelfRoute(url: try #require(entry.playAction?.url))?.action == .play)
        #expect(TVTopShelfRoute(url: try #require(entry.playAction?.url))?.serverIdentifier == "server")
    }

    @Test func cacheClearAndPurgedArtworkProduceNoDynamicContent() throws {
        let cache = temporaryCache()
        defer { try? cache.clear() }
        let filename = try cache.storeImage(jpeg())
        let snapshot = snapshot(filename: filename)
        try cache.write(snapshot)
        try FileManager.default.removeItem(at: #require(cache.imageURL(filename: filename)))
        #expect(TVTopShelfContentBuilder.make(snapshot: snapshot, cache: cache) == nil)
        try cache.clear()
        #expect(try cache.read() == nil)
        #expect(!FileManager.default.fileExists(atPath: cache.directory.path))
        #expect(cache.imageURL(filename: "../../secret.jpg") == nil)
        #expect(cache.imageURL(filename: "https://plex.test/image?X-Plex-Token=secret") == nil)
    }

    @Test func cacheRejectsFutureSchemaAndNativeProgressIsClamped() throws {
        let cache = temporaryCache()
        defer { try? cache.clear() }
        let filename = try cache.storeImage(jpeg())
        let highProgress = snapshot(filename: filename, progress: 2)
        let content = try #require(TVTopShelfContentBuilder.make(snapshot: highProgress, cache: cache))
        #expect(content.sections[0].items[0].playbackProgress == 1)
        var future = highProgress
        future.version += 1
        try cache.write(future)
        #expect(throws: TVTopShelfCache.CacheError.self) { try cache.read() }
        #expect(TVTopShelfContentBuilder.make(snapshot: future, cache: cache) == nil)
    }

    @Test func artworkRetentionStartsAtItsLastPublication() throws {
        let cache = temporaryCache()
        defer { try? cache.clear() }
        let data = jpeg()
        let filename = try cache.storeImage(data)
        let url = try #require(cache.imageURL(filename: filename))
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-172_800)], ofItemAtPath: url.path)
        #expect(try cache.storeImage(data) == filename)
        let empty = TVTopShelfSnapshot(serverIdentifier: "server", sections: [])
        try cache.pruneImages(keeping: empty)
        #expect(FileManager.default.fileExists(atPath: url.path))
        try cache.pruneImages(keeping: empty, now: .now.addingTimeInterval(172_800))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func publisherWritesLocalArtworkAndReplacesPopulatedContentWithEmptyFeed() async throws {
        let cache = temporaryCache()
        defer { try? cache.clear() }
        let image = jpeg()
        let (session, client) = mockClient { request in
            #expect(request.timeoutInterval == 10)
            #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "private-token")
            return (200, image)
        }
        defer { session.invalidateAndCancel() }
        var notifications = 0
        let publisher = TVTopShelfPublisher(cache: { cache }, notify: { notifications += 1 })
        publisher.publish(hubs: [try hub("continueWatching", items: [item(42, type: "episode")])], connection: connection(), client: client)
        await publisher.waitForPublication()
        let published = try #require(try cache.read())
        #expect(published.sections.first?.items.first?.ratingKey == "42")
        let json = String(decoding: try JSONEncoder().encode(published), as: UTF8.self)
        #expect(!json.contains("private-token"))
        #expect(!json.contains("https://"))
        #expect(notifications == 1)
        publisher.publish(hubs: [], connection: connection(), client: client)
        await publisher.waitForPublication()
        #expect(try cache.read()?.sections.isEmpty == true)
        #expect(notifications == 2)
    }

    @Test func publicationCannotRestoreContentAfterClearWhileArtworkIsLoading() async throws {
        let cache = temporaryCache()
        defer { try? cache.clear() }
        let started = AsyncStream<Void>.makeStream()
        let (session, client) = mockClient { _ in
            started.continuation.yield(())
            try await Task.sleep(for: .seconds(30))
            return (200, Data())
        }
        defer { session.invalidateAndCancel() }
        let publisher = TVTopShelfPublisher(cache: { cache }, notify: {})
        publisher.publish(hubs: [try hub("continueWatching", items: [item(42)])], connection: connection(), client: client)
        let publication = Task { await publisher.waitForPublication() }
        var events = started.stream.makeAsyncIterator()
        _ = await events.next()
        publisher.clear()
        await publication.value
        #expect(try cache.read() == nil)
        #expect(!FileManager.default.fileExists(atPath: cache.directory.path))
    }

    @Test func brokenArtworkIsOmittedWithoutAlternateRequests() async throws {
        let cache = temporaryCache()
        defer { try? cache.clear() }
        let requests = Mutex(0)
        let (session, client) = mockClient { _ in
            requests.withLock { $0 += 1 }
            return (200, Data("not an image".utf8))
        }
        defer { session.invalidateAndCancel() }
        let publisher = TVTopShelfPublisher(cache: { cache }, notify: {})
        publisher.publish(hubs: [try hub("continueWatching", items: [item(42)])], connection: connection(), client: client)
        await publisher.waitForPublication()
        #expect(try cache.read()?.sections.isEmpty == true)
        #expect(requests.withLock { $0 } == 1)
    }

    @Test(arguments: [TVTopShelfRoute.Action.display, .play])
    func coldLaunchRouteWaitsForSessionAndFetchesFreshMetadata(action: TVTopShelfRoute.Action) async throws {
        let fixture = try await routingFixture()
        defer { fixture.close() }
        fixture.store.openTopShelfURL(TVTopShelfRoute(action: action, serverIdentifier: "server", ratingKey: "42").url)
        #expect(fixture.store.homePath.isEmpty)
        await fixture.connect()
        #expect(fixture.store.homePath.isEmpty)
        await fixture.store.restoreSession()
        try await waitFor { !fixture.store.homePath.isEmpty }
        let destination = try #require(fixture.store.homePath.first)
        guard case .media(let item) = destination else {
            Issue.record("Top Shelf must open a media destination.")
            return
        }
        #expect(item.ratingKey == "42")
        if action == .play {
            try await waitFor { fixture.store.playbackRequest != nil }
            #expect(fixture.store.playbackRequest?.startTime == 123)
        } else {
            #expect(fixture.store.playbackRequest == nil)
        }
    }

    @Test func routeToAnotherServerDoesNotFetchOrPlayAnUnrelatedTitle() async throws {
        let fixture = try await routingFixture()
        defer { fixture.close() }
        await fixture.connect()
        await fixture.store.restoreSession()
        fixture.store.openTopShelfURL(TVTopShelfRoute(action: .play, serverIdentifier: "another-server", ratingKey: "42").url)
        #expect(fixture.store.errorMessage?.contains("different Plex server") == true)
        #expect(fixture.store.homePath.isEmpty)
        #expect(fixture.store.playbackRequest == nil)
    }

    private func item(_ key: Int, type: String = "movie", artwork: Bool = true) throws -> PlexMediaItem {
        var value: [String: Any] = ["ratingKey": String(key), "title": "Title \(key)", "type": type,
                                    "grandparentTitle": "Series", "parentIndex": 1, "index": 2]
        if artwork { value["thumb"] = "/poster/\(key)"; value["grandparentThumb"] = "/series/poster" }
        return try JSONDecoder().decode(PlexMediaItem.self, from: JSONSerialization.data(withJSONObject: value))
    }

    private func hub(_ identifier: String, title: String = "Recently Added", items: [PlexMediaItem]) throws -> PlexHub {
        var hub = try JSONDecoder().decode(PlexHub.self, from: JSONSerialization.data(withJSONObject: [
            "hubIdentifier": identifier, "title": title
        ]))
        hub.metadata = items
        return hub
    }

    private func temporaryCache() -> TVTopShelfCache {
        TVTopShelfCache(directory: FileManager.default.temporaryDirectory.appending(path: "TopShelfTests-\(UUID())"))
    }

    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        }
    }

    private func snapshot(filename: String, progress: Double = 0) -> TVTopShelfSnapshot {
        .init(serverIdentifier: "server", sections: [.init(identifier: "continueWatching", title: "Continue Watching", items: [
            .init(ratingKey: "42", title: "Continue this episode", imageFilename: filename, shape: .poster, playbackProgress: progress, canPlay: true)
        ])])
    }

    private func connection() -> TVPlexConnection {
        .init(serverURL: URL(string: "https://plex.test")!, token: "private-token", clientIdentifier: "client", serverIdentifier: "server", kind: .local)
    }

    private func mockClient(handler: @escaping TopShelfMockProtocol.Handler) -> (URLSession, TVPlexClient) {
        TopShelfMockProtocol.handler.withLock { $0 = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TopShelfMockProtocol.self]
        let session = URLSession(configuration: configuration)
        return (session, TVPlexClient(session: session))
    }

    private func waitFor(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func routingFixture() async throws -> RoutingFixture {
        let (session, client) = mockClient { request in
            let json: String
            switch request.url?.path {
            case "/identity": json = #"{"MediaContainer":{"machineIdentifier":"server"}}"#
            case "/media/providers":
                json = #"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"promoted","key":"/hubs/promoted"},{"type":"continuewatching","key":"/hubs/continueWatching"}]}]}}"#
            case "/hubs/continueWatching": json = #"{"MediaContainer":{"Hub":[]}}"#
            case "/hubs/promoted": json = #"{"MediaContainer":{"Hub":[]}}"#
            case "/library/sections/all": json = #"{"MediaContainer":{"Directory":[]}}"#
            case "/library/metadata/42":
                json = #"{"MediaContainer":{"Metadata":[{"ratingKey":"42","type":"movie","title":"Fresh title","viewOffset":123000,"duration":300000,"Media":[{"Part":[{"key":"/file.mp4"}]}]}]}}"#
            default: return (404, Data())
            }
            return (200, Data(json.utf8))
        }
        let cache = temporaryCache()
        let suite = "TopShelfRoutingTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let publisher = TVTopShelfPublisher(cache: { cache }, notify: {})
        let accountStorage = TVPlexAccountJWTStorage(defaults: defaults, credentialStore: PlexMemoryCredentialStore(
            credentials: PlexStoredCredentials(userToken: "test-account", serverToken: "")
        ))
        try await accountStorage.loadAccountToken()
        let store = TVAppStore(client: client, defaults: defaults, keychain: KeychainStore(service: suite), topShelfPublisher: publisher, accountStorage: accountStorage)
        return RoutingFixture(store: store, session: session, defaults: defaults, suite: suite, cache: cache, publisher: publisher)
    }

    @MainActor
    private struct RoutingFixture {
        let store: TVAppStore
        let session: URLSession
        let defaults: UserDefaults
        let suite: String
        let cache: TVTopShelfCache
        let publisher: TVTopShelfPublisher

        func connect() async {
            let server = PlexServerResource(id: "server", name: "Server", productVersion: nil, accessToken: "private-token", connections: [
                .init(uri: URL(string: "https://plex.test")!, local: true, relay: false)
            ])
            store.availableServers = [server]
            await store.selectServer(server)
        }

        func close() {
            publisher.clear()
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}

private final class TopShelfMockProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Int, Data)
    static let handler = Mutex<Handler?>(nil)
    private let loadingTask = Mutex<Task<Void, Never>?>(nil)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler.withLock({ $0 }) else { return }
        let loading = Task { @Sendable [self, request = request] in
            do {
                let (status, data) = try await handler(request)
                try Task.checkCancellation()
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        loadingTask.withLock { $0 = loading }
    }
    override func stopLoading() { loadingTask.withLock { $0?.cancel() } }
}
#endif
