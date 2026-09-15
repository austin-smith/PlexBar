import PlexModels
#if os(tvOS)
import Foundation
import Synchronization
import Testing
@testable import PlexBarTV

@Suite(.serialized, .timeLimit(.minutes(1)))
struct TVMediaDetailTests {
    @MainActor
    @Test func anExtraDoesNotRequestItsOwnExtras() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let suiteName = "TVMediaDetailTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TVAppStore(client: fixture.client, defaults: defaults)
        let clip = try item(#"{"ratingKey":"42","type":"clip","title":"Trailer"}"#)
        #expect(try await store.mediaExtras(for: clip).isEmpty)
        #expect(TVDetailMockProtocol.requests.withLock { $0.isEmpty })
    }

    @Test func episodeWithoutCreditsLoadsItsActualSeriesCast() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let episode = try item(#"{"ratingKey":"42","type":"episode","title":"Episode","grandparentRatingKey":"7"}"#)
        let cast = try await fixture.client.fetchEpisodeSeriesCast(for: episode, connection: fixture.connection)
        let presentation = PlexCastAndCrewPresentation(item: episode, episodeSeriesCast: cast)
        #expect(presentation.cast.map(\.name) == ["Series Lead"])
        #expect(presentation.cast.first?.subtitle == "Character")
        #expect(TVDetailMockProtocol.requests.withLock { $0.map { $0.url?.path } } == ["/library/metadata/7"])
    }

    @Test func episodeCreditsDoNotTriggerARequestOrGetReplacedBySeriesCredits() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let episode = try item(#"{"ratingKey":"42","type":"episode","title":"Episode","grandparentRatingKey":"7","Role":[{"id":8,"tag":"Guest Star","role":"Guest"}]}"#)
        let cast = try await fixture.client.fetchEpisodeSeriesCast(for: episode, connection: fixture.connection)
        #expect(cast.isEmpty)
        #expect(PlexCastAndCrewPresentation(item: episode, episodeSeriesCast: cast).cast.map(\.name) == ["Guest Star"])
        #expect(TVDetailMockProtocol.requests.withLock { $0.isEmpty })
    }

    @Test(arguments: [
        #"{"ratingKey":"8","type":"show","title":"Wrong Series"}"#,
        #"{"ratingKey":"7","type":"movie","title":"Wrong Type"}"#
    ])
    func mismatchedSeriesMetadataIsRejected(metadata: String) async throws {
        let fixture = Fixture(metadata: metadata)
        defer { fixture.close() }
        let episode = try item(#"{"ratingKey":"42","type":"episode","title":"Episode","grandparentRatingKey":"7"}"#)
        await #expect(throws: TVPlexError.self) {
            try await fixture.client.fetchEpisodeSeriesCast(for: episode, connection: fixture.connection)
        }
    }

    @Test func serverFailureIsNotReportedAsAnEmptyCast() async throws {
        let fixture = Fixture(status: 500)
        defer { fixture.close() }
        let episode = try item(#"{"ratingKey":"42","type":"episode","title":"Episode","grandparentRatingKey":"7"}"#)
        await #expect(throws: TVPlexError.self) {
            try await fixture.client.fetchEpisodeSeriesCast(for: episode, connection: fixture.connection)
        }
    }

    private func item(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }

    @Test func extrasUseTheMacOSRouteAndSharedSubtypeLabels() async throws {
        let fixture = Fixture(body: #"{"MediaContainer":{"Metadata":[{"ratingKey":"91","type":"clip","title":"Interview","subtype":"interview"},{"ratingKey":"90","type":"clip","title":"Trailer","subtype":"trailer"}]}}"#)
        defer { fixture.close() }
        let extras = try await fixture.client.fetchMediaExtras(ratingKey: "42", connection: fixture.connection)
        #expect(extras.map(\.ratingKey) == ["91", "90"])
        #expect(extras.map(\.subtitle) == ["Interview", "Trailer"])
        #expect(TVDetailMockProtocol.requests.withLock { $0.first?.url?.path } == "/library/metadata/42/extras")
    }

    @Test func relatedHubsPreserveServerOrderAndPaginationInformation() async throws {
        let fixture = Fixture(body: #"{"MediaContainer":{"Hub":[{"hubIdentifier":"empty","title":"Empty","Metadata":[]},{"hubIdentifier":"similar","title":"More Like This","more":true,"totalSize":20,"key":"/library/metadata/42/similar","Metadata":[{"ratingKey":"8","type":"movie","title":"Related"}]}]}}"#)
        defer { fixture.close() }
        let hubs = try await fixture.client.fetchRelatedHubs(ratingKey: "42", connection: fixture.connection)
        #expect(hubs.map(\.title) == ["More Like This"])
        #expect(hubs.first?.more == true)
        #expect(hubs.first?.totalSize == 20)
        let url = try #require(TVDetailMockProtocol.requests.withLock { $0.first?.url })
        #expect(url.path == "/hubs/metadata/42/related")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "count", value: "12")) == true)
    }

    @Test(arguments: ["extras", "related"])
    func discoveryFailureDoesNotBecomeEmptyContent(endpoint: String) async throws {
        let fixture = Fixture(status: 500)
        defer { fixture.close() }
        await #expect(throws: TVPlexError.self) {
            if endpoint == "extras" {
                _ = try await fixture.client.fetchMediaExtras(ratingKey: "42", connection: fixture.connection)
            } else {
                _ = try await fixture.client.fetchRelatedHubs(ratingKey: "42", connection: fixture.connection)
            }
        }
    }

    private struct Fixture {
        let client: TVPlexClient
        let session: URLSession
        let connection = TVPlexConnection(
            serverURL: URL(string: "https://plex.test")!, token: "test-token",
            clientIdentifier: "detail-tests", serverIdentifier: "test-server", kind: .local
        )

        init(
            metadata: String = #"{"ratingKey":"7","type":"show","title":"Series","Role":[{"id":1,"tag":"Series Lead","role":"Character"}]}"#,
            status: Int = 200,
            body: String? = nil
        ) {
            TVDetailMockProtocol.requests.withLock { $0 = [] }
            TVDetailMockProtocol.response.withLock {
                $0 = (status, Data((body ?? "{\"MediaContainer\":{\"Metadata\":[\(metadata)]}}").utf8))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [TVDetailMockProtocol.self]
            session = URLSession(configuration: configuration)
            client = TVPlexClient(session: session)
        }

        func close() { session.invalidateAndCancel() }
    }
}

private final class TVDetailMockProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    static let response = Mutex<(Int, Data)>((200, Data()))

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let (status, data) = Self.response.withLock { $0 }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
