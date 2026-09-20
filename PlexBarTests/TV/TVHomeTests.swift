import PlexModels
#if os(tvOS)
@testable import PlexClientKit
import Foundation
import Synchronization
import Testing
@testable import PlexBarTV

@Suite(.serialized)
struct TVHomeTests {
    @Test func unifiedFeedReplacesBothLegacyRowsAndPreservesServerOrderAndPaging() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let hubs = try await fixture.home()
        #expect(hubs.map(\.hubIdentifier) == ["continueWatching", "recent.movies", "recent.tv"])
        let hub = try #require(hubs.first)
        #expect(hub.metadata.map(\.ratingKey) == ["next", "paused"])
        #expect(hub.isContinueWatching)
        #expect(hub.prefersPosterArtwork)
        #expect(hub.title == "Continuer")
        #expect(hub.more)
        #expect(hub.totalSize == 3)
        let path = try #require(hub.key)
        let page = try await fixture.page(path: path)
        #expect(page.items.map(\.ratingKey) == ["last"])
        #expect(page.totalSize == 3)
        let requests = HomeProtocol.requests.withLock { $0 }
        let feed = try #require(requests.first { $0.url?.path == "/custom/continue" })
        let query = try #require(URLComponents(url: feed.url!, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "source", value: "library")))
        #expect(query.contains(URLQueryItem(name: "count", value: "20")))
        #expect(feed.value(forHTTPHeaderField: "X-Plex-Token") == "test-token")
        let expanded = try #require(requests.first { $0.url?.path == "/custom/continue/items" })
        #expect(expanded.value(forHTTPHeaderField: "X-Plex-Container-Start") == "2")
        #expect(expanded.url?.query == "source=library")
        #expect(!requests.contains { $0.url?.path == "/hubs/home/onDeck" })
    }

    @Test func homeExcludesAudioShelvesAndMixedAudioItemsByMediaType() async throws {
        let fixture = Fixture(continuation: #"{"MediaContainer":{"Hub":[{"hubIdentifier":"continueWatching","title":"Continue Watching","Metadata":[{"ratingKey":"book","type":"track","title":"Spoken chapter"},{"ratingKey":"next","type":"episode","title":"Next episode"}]}]}}"#)
        defer { fixture.close() }
        let hubs = try await fixture.home()
        #expect(hubs.map(\.hubIdentifier) == ["continueWatching", "recent.movies", "recent.tv"])
        #expect(hubs.first?.metadata.map(\.ratingKey) == ["next"])
        #expect(hubs.flatMap(\.metadata).allSatisfy { ["movie", "episode"].contains($0.type) })
    }

    @Test func emptyUnifiedFeedDoesNotResurrectLegacyItems() async throws {
        let fixture = Fixture(continuation: #"{"MediaContainer":{"Hub":[{"hubIdentifier":"continueWatching","title":"Continue Watching","Metadata":[]}]}}"#)
        defer { fixture.close() }
        let hubs = try await fixture.home()
        #expect(hubs.map(\.hubIdentifier) == ["recent.movies", "recent.tv"])
    }

    @Test func failedUnifiedFeedSurfacesTheError() async throws {
        let fixture = Fixture(status: 503)
        defer { fixture.close() }
        do {
            _ = try await fixture.home()
            Issue.record("Expected unified feed failure")
        } catch {
            #expect(error.localizedDescription.contains("503"))
        }
    }

    @Test func missingUnifiedCapabilityDoesNotRequestLegacyHome() async throws {
        let fixture = Fixture(advertisesContinuation: false)
        defer { fixture.close() }
        do {
            _ = try await fixture.home()
            Issue.record("Expected missing Continue Watching capability")
        } catch let error as PlexAPIError {
            guard case .missingLibraryContinueWatchingFeature = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
        #expect(!HomeProtocol.requests.withLock { $0.contains { $0.url?.path == "/custom/promoted" } })
    }

    @Test func splitResponseFromUnifiedEndpointIsRejected() async throws {
        let fixture = Fixture(continuation: HomeProtocol.promoted)
        defer { fixture.close() }
        do {
            _ = try await fixture.home()
            Issue.record("Expected malformed unified response failure")
        } catch let error as PlexAPIError {
            guard case .invalidResponse = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    private struct Fixture {
        let session: URLSession
        let advertisesContinuation: Bool
        init(continuation: String = HomeProtocol.unified, status: Int = 200, advertisesContinuation: Bool = true) {
            self.advertisesContinuation = advertisesContinuation
            HomeProtocol.requests.withLock { $0 = [] }
            HomeProtocol.response.withLock { $0 = (continuation, status, advertisesContinuation) }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [HomeProtocol.self]
            session = URLSession(configuration: configuration)
        }
        var connection: TVPlexConnection {
            TVPlexConnection(serverURL: URL(string: "https://plex.test")!, token: "test-token",
                             clientIdentifier: "home-tests", serverIdentifier: "server", kind: .local)
        }
        func home() async throws -> [PlexHub] {
            try await TVPlexClient(session: session).fetchHome(connection: connection)
        }
        func page(path: String) async throws -> PlexMediaPage {
            try await TVPlexClient(session: session).fetchHubPage(path: path, start: 2, connection: connection)
        }
        func close() { session.invalidateAndCancel() }
    }
}

private final class HomeProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    static let response = Mutex<(String, Int, Bool)>((unified, 200, true))
    static let unified = #"{"MediaContainer":{"Hub":[{"hubIdentifier":"continueWatching","title":"Continuer","key":"/custom/continue/items?source=library","more":true,"size":2,"totalSize":3,"Metadata":[{"ratingKey":"next","type":"episode","title":"Next episode"},{"ratingKey":"paused","type":"movie","title":"Paused movie","viewOffset":60000}]}]}}"#
    static let promoted = #"{"MediaContainer":{"Hub":[{"hubIdentifier":"recent.audio","title":"Comedy","Metadata":[{"ratingKey":"book","type":"album","title":"A book"}]},{"hubIdentifier":"recent.music","title":"New releases","Metadata":[{"ratingKey":"musician","type":"artist","title":"An artist"}]},{"hubIdentifier":"recent.movies","title":"Movies","Metadata":[{"ratingKey":"paused","type":"movie","title":"Paused movie"}]},{"hubIdentifier":"home.continue","title":"Old Continue Watching","Metadata":[{"ratingKey":"paused","type":"movie","title":"Paused movie"}]},{"hubIdentifier":"home.onDeck","title":"On Deck","Metadata":[{"ratingKey":"next","type":"episode","title":"Next episode"},{"ratingKey":"stale","type":"episode","title":"Excluded episode"}]},{"hubIdentifier":"continueWatching","title":"Promoted duplicate","Metadata":[{"ratingKey":"stale","type":"episode","title":"Excluded episode"}]},{"hubIdentifier":"recent.tv","title":"TV","Metadata":[{"ratingKey":"next","type":"episode","title":"Next episode"}]}]}}"#
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let state = Self.response.withLock { $0 }
        let json: String
        var status = 200
        switch request.url?.path {
        case "/media/providers":
            let continuation = state.2 ? #",{"type":"ContinueWatching","key":"/custom/continue?source=library"}"# : ""
            json = #"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"promoted","key":"/custom/promoted?source=library"}\#(continuation)]}]}}"#
        case "/custom/promoted": json = Self.promoted
        case "/custom/continue": (json, status) = (state.0, state.1)
        case "/custom/continue/items":
            json = #"{"MediaContainer":{"offset":2,"totalSize":3,"Metadata":[{"ratingKey":"last","type":"episode","title":"Last episode"}]}}"#
        default:
            json = "{}"
            status = 404
        }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
