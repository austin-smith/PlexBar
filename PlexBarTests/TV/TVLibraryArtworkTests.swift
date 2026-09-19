#if os(tvOS)
@testable import PlexClientKit
import Foundation
import Testing
import Synchronization
@testable import PlexBarTV

@MainActor
struct TVLibraryArtworkTests {
    @Test func librarySummariesSupplyArtworkWhenSectionsHaveNoImages() async throws {
        LibraryArtworkProtocol.requests.withLock { $0 = [] }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryArtworkProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let connection = TVPlexConnection(
            serverURL: URL(string: "https://plex.test")!, token: "artwork-test-token",
            clientIdentifier: "artwork-tests", serverIdentifier: "server", kind: .local
        )
        let libraries = try await TVPlexClient(session: session).fetchLibraries(connection: connection)
        #expect(libraries.map(\.id) == ["3", "4", "7", "9"])
        #expect(libraries.map(\.artworkPath) == ["/art/movie", "/thumb/show", "/art/artist", nil])
        let requests = LibraryArtworkProtocol.requests.withLock { $0 }
        #expect(requests.count == 5)
        #expect(requests.contains { $0.url?.path == "/library/sections/all" })
        for request in requests where request.url?.path != "/library/sections/all" {
            #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Start") == "0")
            #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "1")
            #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "artwork-test-token")
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "sort", value: "addedAt:desc")])
        }
    }

    @Test func libraryCardUsesServerCompositeInsteadOfGenericResourceArt() async throws {
        let library = try JSONDecoder().decode(TVPlexLibrary.self, from: Data(#"{"key":"1","title":"Movies","type":"movie","composite":"/library/sections/1/composite/1706626696?width=960","art":"/:/resources/movie-fanart.jpg","thumb":"/:/resources/movie.png"}"#.utf8))
        #expect(library.artworkPath == "/library/sections/1/composite/1706626696?width=960")
        let connection = TVPlexConnection(
            serverURL: URL(string: "https://plex.test")!, token: "artwork-test-token",
            clientIdentifier: "artwork-tests", serverIdentifier: "server", kind: .local
        )
        let client = TVPlexClient()
        let url = try #require(await client.artworkURL(
            path: library.artworkPath, width: 960, height: 540,
            connection: connection, usesOriginalImage: true
        ))
        #expect(url.path == "/library/sections/1/composite/1706626696")
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "width", value: "960")))
        #expect(query.contains(URLQueryItem(name: "X-Plex-Token", value: "artwork-test-token")))
    }

    @Test func blankCompositeDoesNotHideAnExplicitLibraryImage() throws {
        let library = try JSONDecoder().decode(TVPlexLibrary.self, from: Data(#"{"key":"1","title":"Movies","type":"movie","composite":"  ","art":"/library/sections/1/art"}"#.utf8))
        #expect(library.composite == nil)
        #expect(library.artworkPath == "/library/sections/1/art")
    }
}
private final class LibraryArtworkProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let json: String
        switch request.url?.path {
        case "/library/sections/all":
            json = #"{"MediaContainer":{"Directory":[{"key":"3","title":"Movies","type":"movie"},{"key":"4","title":"TV Shows","type":"show"},{"key":"7","title":"Audiobooks","type":"artist"},{"key":"9","title":"Empty","type":"movie"}]}}"#
        case "/library/sections/3/all":
            json = #"{"MediaContainer":{"Metadata":[{"ratingKey":"30","title":"Movie","type":"movie","art":"/art/movie","thumb":"/thumb/movie"}]}}"#
        case "/library/sections/4/all":
            json = #"{"MediaContainer":{"Metadata":[{"ratingKey":"40","title":"Show","type":"show","thumb":"/thumb/show"}]}}"#
        case "/library/sections/7/all":
            json = #"{"MediaContainer":{"Metadata":[{"ratingKey":"70","title":"Author","type":"artist","art":"/art/artist"}]}}"#
        default:
            json = #"{"MediaContainer":{"Metadata":[]}}"#
        }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
