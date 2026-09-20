@testable import PlexClientKit
import PlexModels
import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexCollectionPlaylistRequestTests {
    @Test func collectionsUseTheSectionEndpointAndDecodeTheirReturnedItemKey() async throws {
        let capture = RequestCapture()
        let session = makeCollectionPlaylistMockSession { request in
            capture.record(request)
            return try response(for: request, data: collectionPageData())
        }

        let page = try await PlexAPIClient(session: session).fetchCollectionsPage(
            libraryID: "26",
            using: try configuration,
            start: 100,
            size: 50
        )

        let request = try #require(capture.request)
        #expect(request.url?.path == "/library/sections/26/collections")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Start") == "100")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "50")
        #expect(page.items.first?.childrenPath == "/library/collections/900/items")
        #expect(page.items.first?.preferredArtworkPath == "/library/collections/900/composite/12")
        #expect(page.totalSize == 1)
    }

    @Test func playlistsRequestTheServerHierarchyAndDecodeFoldersAndPlaylists() async throws {
        let capture = RequestCapture()
        let session = makeCollectionPlaylistMockSession { request in
            capture.record(request)
            return try response(for: request, data: playlistPageData())
        }

        let page = try await PlexAPIClient(session: session).fetchPlaylistsPage(
            endpointPath: "/provider/playlists?source=library",
            using: try configuration,
            start: 25,
            size: 25
        )

        let request = try #require(capture.request)
        let components = try #require(
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        )
        #expect(components.path == "/provider/playlists")
        #expect(queryValue("source", in: request) == "library")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Start") == "25")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "25")
        #expect(page.items.first?.type == "playlistfolder")
        #expect(page.items.first?.childrenPath == "/playlists/folders/700/children?owned=1")
        #expect(page.items.first?.hasChildren == true)
        #expect(page.items.last?.childrenPath == "/playlists/901/items")
        #expect(page.items.last?.playlistType == "video")
        #expect(page.items.last?.smart == true)
    }

    @Test func duplicatePlaylistEntriesUsePlaylistItemIdentity() throws {
        let first = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"42","playlistItemID":"1001","title":"Charade"}"#.utf8)
        )
        let second = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"42","playlistItemID":1002,"title":"Charade"}"#.utf8)
        )

        #expect(first.ratingKey == second.ratingKey)
        #expect(first.id == "playlist-item:1001")
        #expect(second.id == "playlist-item:1002")
        #expect(first.id != second.id)
    }

    @Test func collectionMutationsUseDocumentedMethodsPathsAndIdentifiers() async throws {
        let log = MutationRequestLog()
        let session = makeCollectionPlaylistMockSession { request in
            log.record(request)
            return try response(for: request, data: collectionPageData())
        }
        let client = PlexAPIClient(session: session)

        let created = try await client.createCollection(
            title: "Silent Films",
            libraryID: "26",
            metadataTypeID: 1,
            endpointPath: "/provider/collections?source=library",
            using: try configuration
        )
        try await client.renameCollection(
            id: "900",
            title: "Pre-Code",
            metadataEndpointPath: "/provider/metadata?source=library",
            using: try configuration
        )
        try await client.deleteCollection(
            id: "900",
            libraryID: "26",
            using: try configuration
        )
        try await client.removeCollectionItem(
            id: "42",
            fromCollectionID: "900",
            endpointPath: "/provider/collections?source=library",
            using: try configuration
        )
        try await client.moveCollectionItem(
            id: "42",
            inCollectionID: "900",
            afterItemID: "41",
            endpointPath: "/provider/collections?source=library",
            using: try configuration
        )
        try await client.moveCollectionItem(
            id: "42",
            inCollectionID: "900",
            afterItemID: nil,
            endpointPath: "/provider/collections?source=library",
            using: try configuration
        )

        #expect(created.ratingKey == "900")
        let requests = log.requests
        #expect(requests.count == 6)
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.path == "/provider/collections")
        #expect(queryValue("source", in: requests[0]) == "library")
        #expect(queryValue("sectionId", in: requests[0]) == "26")
        #expect(queryValue("title", in: requests[0]) == "Silent Films")
        #expect(queryValue("smart", in: requests[0]) == "0")
        #expect(queryValue("type", in: requests[0]) == "1")
        #expect(requests[1].httpMethod == "PUT")
        #expect(requests[1].url?.path == "/provider/metadata/900")
        #expect(queryValue("source", in: requests[1]) == "library")
        #expect(queryValue("title", in: requests[1]) == "Pre-Code")
        #expect(requests[2].httpMethod == "DELETE")
        #expect(requests[2].url?.path == "/library/sections/26/collection/900")
        #expect(requests[3].httpMethod == "PUT")
        #expect(requests[3].url?.path == "/provider/collections/900/items/42")
        #expect(queryValue("source", in: requests[3]) == "library")
        #expect(requests[4].httpMethod == "PUT")
        #expect(requests[4].url?.path == "/provider/collections/900/items/42/move")
        #expect(queryValue("source", in: requests[4]) == "library")
        #expect(queryValue("after", in: requests[4]) == "41")
        #expect(requests[5].url?.path == "/provider/collections/900/items/42/move")
        #expect(queryValue("source", in: requests[5]) == "library")
    }

    @Test func playlistMutationsUsePlaylistItemIdentityForRemovalAndMoves() async throws {
        let log = MutationRequestLog()
        let session = makeCollectionPlaylistMockSession { request in
            log.record(request)
            return try response(for: request, data: Data())
        }
        let client = PlexAPIClient(session: session)

        try await client.renamePlaylist(
            id: "901",
            title: "Friday",
            endpointPath: "/provider/playlists?source=library",
            using: try configuration
        )
        try await client.deletePlaylist(
            id: "901",
            endpointPath: "/provider/playlists?source=library",
            using: try configuration
        )
        try await client.removePlaylistItem(
            playlistItemID: "1002",
            fromPlaylistID: "901",
            endpointPath: "/provider/playlists?source=library",
            using: try configuration
        )
        try await client.movePlaylistItem(
            playlistItemID: "1002",
            inPlaylistID: "901",
            afterPlaylistItemID: "1003",
            endpointPath: "/provider/playlists?source=library",
            using: try configuration
        )
        try await client.movePlaylistItem(
            playlistItemID: "1002",
            inPlaylistID: "901",
            afterPlaylistItemID: nil,
            endpointPath: "/provider/playlists?source=library",
            using: try configuration
        )

        let requests = log.requests
        #expect(requests.count == 5)
        #expect(requests[0].httpMethod == "PUT")
        #expect(requests[0].url?.path == "/provider/playlists/901")
        #expect(queryValue("source", in: requests[0]) == "library")
        #expect(queryValue("title", in: requests[0]) == "Friday")
        #expect(requests[1].httpMethod == "DELETE")
        #expect(requests[1].url?.path == "/provider/playlists/901")
        #expect(queryValue("source", in: requests[1]) == "library")
        #expect(requests[2].httpMethod == "DELETE")
        #expect(requests[2].url?.path == "/provider/playlists/901/items/1002")
        #expect(queryValue("source", in: requests[2]) == "library")
        #expect(requests[3].httpMethod == "PUT")
        #expect(requests[3].url?.path == "/provider/playlists/901/items/1002/move")
        #expect(queryValue("source", in: requests[3]) == "library")
        #expect(queryValue("after", in: requests[3]) == "1003")
        #expect(requests[4].url?.path == "/provider/playlists/901/items/1002/move")
        #expect(queryValue("source", in: requests[4]) == "library")
    }

    @Test func addAndCreateRequestsUseTheCanonicalServerItemURI() async throws {
        let log = MutationRequestLog()
        let session = makeCollectionPlaylistMockSession { request in
            log.record(request)
            let data = request.httpMethod == "POST" && request.url?.path == "/provider/playlists"
                ? createdPlaylistData()
                : Data()
            return try response(for: request, data: data)
        }
        let client = PlexAPIClient(session: session)
        let item = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(
                #"{"ratingKey":"42","key":"/library/metadata/42","type":"movie","title":"Charade"}"#.utf8
            )
        )
        let uri = try PlexMediaSourceURI.item(item, serverIdentifier: "server-id")

        #expect(uri == "server://server-id/com.plexapp.plugins.library/library/metadata/42")

        try await client.addItem(
            uri: uri,
            toCollectionID: "900",
            endpointPath: "/provider/collections?source=library",
            using: try configuration
        )
        let playlist = try await client.createPlaylist(
            containingItemURI: uri,
            endpointPath: "/provider/playlists?source=library",
            using: try configuration
        )
        try await client.addItem(
            uri: uri,
            toPlaylistID: playlist.ratingKey,
            endpointPath: "/provider/playlists?source=library",
            using: try configuration
        )

        let requests = log.requests
        #expect(requests.count == 3)
        #expect(requests[0].httpMethod == "PUT")
        #expect(requests[0].url?.path == "/provider/collections/900/items")
        #expect(queryValue("source", in: requests[0]) == "library")
        #expect(queryValue("uri", in: requests[0]) == uri)
        #expect(requests[1].httpMethod == "POST")
        #expect(requests[1].url?.path == "/provider/playlists")
        #expect(queryValue("source", in: requests[1]) == "library")
        #expect(queryValue("uri", in: requests[1]) == uri)
        #expect(playlist.ratingKey == "901")
        #expect(requests[2].httpMethod == "PUT")
        #expect(requests[2].url?.path == "/provider/playlists/901/items")
        #expect(queryValue("source", in: requests[2]) == "library")
        #expect(queryValue("uri", in: requests[2]) == uri)
    }

    @Test func blankMutationTitlesAreRejectedBeforeARequestIsSent() async throws {
        let log = MutationRequestLog()
        let session = makeCollectionPlaylistMockSession { request in
            log.record(request)
            return try response(for: request, data: collectionPageData())
        }
        let client = PlexAPIClient(session: session)

        await #expect(throws: PlexAPIError.self) {
            _ = try await client.createCollection(
                title: "  \n",
                libraryID: "26",
                metadataTypeID: 1,
                endpointPath: "/provider/collections",
                using: try configuration
            )
        }
        await #expect(throws: PlexAPIError.self) {
            try await client.renamePlaylist(
                id: "901",
                title: "",
                endpointPath: "/provider/playlists",
                using: try configuration
            )
        }

        #expect(log.requests.isEmpty)
    }

    private var configuration: PlexConnectionConfiguration {
        get throws {
            PlexConnectionConfiguration(
                serverURL: try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400")),
                token: "server-token",
                clientContext: PlexClientContext(clientIdentifier: "client-123")
            )
        }
    }
}

private final class MutationRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    func record(_ request: URLRequest) {
        lock.withLock {
            recordedRequests.append(request)
        }
    }
}

private func queryValue(_ name: String, in request: URLRequest) -> String? {
    request.url
        .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        .flatMap(\.queryItems)?
        .first(where: { $0.name == name })?
        .value
}

private func response(for request: URLRequest, data: Data) throws -> (HTTPURLResponse, Data) {
    let response = try #require(HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["X-Plex-Container-Total-Size": "1"]
    ))
    return (response, data)
}

private func collectionPageData() -> Data {
    Data(#"""
    {
      "MediaContainer": {
        "offset": 100,
        "Metadata": [{
          "ratingKey": "900",
          "key": "/library/collections/900/items",
          "type": "collection",
          "title": "Silent Films",
          "composite": "/library/collections/900/composite/12",
          "leafCount": "2"
        }]
      }
    }
    """#.utf8)
}

private func playlistPageData() -> Data {
    Data(#"""
    {
      "MediaContainer": {
        "offset": 25,
        "Metadata": [{
          "ratingKey": "700",
          "key": "/playlists/folders/700/children?owned=1",
          "type": "playlistfolder",
          "title": "Weekend"
        }, {
          "ratingKey": "901",
          "key": "/playlists/901/items",
          "type": "playlist",
          "title": "Movie Night",
          "composite": "/playlists/901/composite/12",
          "duration": 7200000,
          "leafCount": 2,
          "playlistType": "video",
          "smart": "1"
        }]
      }
    }
    """#.utf8)
}

private func createdPlaylistData() -> Data {
    Data(#"""
    {
      "MediaContainer": {
        "Metadata": [{
          "ratingKey": "901",
          "key": "/playlists/901/items",
          "type": "playlist",
          "title": "Playlist",
          "playlistType": "video",
          "smart": false,
          "readOnly": false
        }]
      }
    }
    """#.utf8)
}

private func makeCollectionPlaylistMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    CollectionPlaylistMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CollectionPlaylistMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class CollectionPlaylistMockURLProtocol: URLProtocol, @unchecked Sendable {
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
