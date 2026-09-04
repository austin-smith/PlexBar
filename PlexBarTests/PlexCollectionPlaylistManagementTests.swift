import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
@MainActor
struct PlexCollectionPlaylistManagementTests {
    @Test func collectionCreateRenameAndDeletePublishOnlyServerConfirmedState() async throws {
        let scenario = CollectionManagementScenario(canManage: true)
        let store = try makeStore { request in
            try scenario.response(for: request)
        }
        let library = makeLibrary()

        await store.loadLibraryProviderCapabilities()
        #expect(store.supportsCollectionManagement)

        _ = try await store.createCollection(named: "Silent Films", in: library)
        let created = try #require(store.collections(in: library).first)
        #expect(created.title == "Silent Films")

        try await store.renameCollection(created, to: "Pre-Code", in: library)
        let renamed = try #require(store.collections(in: library).first)
        #expect(renamed.title == "Pre-Code")

        try await store.deleteCollection(renamed, in: library)
        #expect(store.collections(in: library).isEmpty)
        #expect(scenario.methodsAndPaths == [
            "GET /media/providers",
            "POST /provider/collections",
            "GET /library/sections/26/collections",
            "PUT /provider/metadata/900",
            "GET /library/sections/26/collections",
            "DELETE /library/sections/26/collection/900",
        ])
    }

    @Test func collectionManagementIsUnavailableWithoutTheManageFeature() async throws {
        let scenario = CollectionManagementScenario(canManage: false)
        let store = try makeStore { request in
            try scenario.response(for: request)
        }
        let library = makeLibrary()

        await store.loadLibraryProviderCapabilities()
        #expect(!store.supportsCollectionManagement)

        await #expect(throws: PlexAPIError.self) {
            _ = try await store.createCollection(named: "No Access", in: library)
        }
        #expect(scenario.methodsAndPaths == [
            "GET /media/providers",
        ])
    }

    @Test func collectionManagementFailsClosedWithoutAnAdvertisedCollectionEndpoint() async throws {
        let scenario = MissingCollectionFeatureScenario()
        let store = try makeStore { request in
            try scenario.response(for: request)
        }
        let library = makeLibrary()

        await store.loadLibraryProviderCapabilities()
        #expect(!store.supportsCollectionManagement)

        await #expect(throws: PlexAPIError.self) {
            _ = try await store.createCollection(named: "Unavailable", in: library)
        }
        #expect(scenario.methodsAndPaths == [
            "GET /media/providers",
        ])
    }

    @Test func createAndAddReportsTheCreatedCollectionWhenAddingFails() async throws {
        let scenario = CollectionCreateAndAddFailureScenario()
        let store = try makeStore { request in
            try scenario.response(for: request)
        }
        let library = makeLibrary()
        let movie = try decodeItem(
            #"{"ratingKey":"42","key":"/library/metadata/42","type":"movie","title":"Charade"}"#
        )

        await store.loadLibraryProviderCapabilities()

        do {
            try await store.createCollection(
                named: "Cary Grant",
                containing: movie,
                in: library
            )
            Issue.record("Expected adding the item to fail after the collection was created")
        } catch let error as PlexBrowserMutationError {
            #expect(
                error.localizedDescription
                    == "Plex created Cary Grant, but the item was not added. You can add it to that collection after retrying the connection."
            )
        }

        #expect(store.collections(in: library).map(\.title) == ["Cary Grant"])
        #expect(scenario.methodsAndPaths == [
            "GET /media/providers",
            "POST /provider/collections",
            "GET /library/sections/26/collections",
            "PUT /provider/collections/900/items",
        ])
    }

    @Test func confirmedCollectionAddDoesNotBecomeAFailedAddWhenRefreshFails() async throws {
        let scenario = CollectionAddRefreshFailureScenario()
        let store = try makeStore { request in
            try scenario.response(for: request)
        }
        let library = makeLibrary()
        let movie = try decodeItem(
            #"{"ratingKey":"42","key":"/library/metadata/42","type":"movie","title":"Charade"}"#
        )

        await store.loadLibraryProviderCapabilities()
        await store.loadCollections(in: library)
        let collection = try #require(store.collections(in: library).first)

        try await store.add(movie, to: collection, in: library)

        #expect(scenario.addRequestCount == 1)
        #expect(
            store.collectionsErrorMessage(in: library)
                == "Plex returned HTTP 500. Check the server URL and token."
        )
    }

    @Test func playlistMovesAndRemovalUsePlaylistItemIDsThenReloadChildren() async throws {
        let scenario = PlaylistChildrenManagementScenario()
        let store = try makeStore { request in
            try scenario.response(for: request)
        }
        let playlist = try decodeItem(
            #"{"ratingKey":"901","key":"/playlists/901/items","type":"playlist","title":"Friday","smart":false,"readOnly":false}"#
        )

        await store.loadLibraryProviderCapabilities()
        await store.loadChildren(of: playlist)
        let middle = try #require(store.children(of: playlist).dropFirst().first)
        #expect(store.canMoveChild(middle, in: playlist, direction: .down))

        try await store.moveChild(middle, in: playlist, direction: .down)
        #expect(store.children(of: playlist).map(\.playlistItemID) == ["1001", "1003", "1002"])

        let moved = try #require(store.children(of: playlist).last)
        try await store.removeChild(moved, from: playlist)
        #expect(store.children(of: playlist).map(\.playlistItemID) == ["1001", "1003"])
        #expect(scenario.methodsPathsAndQueries == [
            "GET /media/providers",
            "GET /playlists/901/items",
            "PUT /provider/playlists/901/items/1002/move?source=library&after=1003",
            "GET /playlists/901/items",
            "DELETE /provider/playlists/901/items/1002?source=library",
            "GET /playlists/901/items",
        ])
    }

    @Test func smartAndReadOnlyPlaylistsNeverExposeItemManagement() async throws {
        let store = try makeStore { request in
            if request.url?.path == "/media/providers" {
                return try managementResponse(for: request, data: providerData(canManage: true))
            }
            return try emptyResponse(for: request)
        }
        let smart = try decodeItem(
            #"{"ratingKey":"1","key":"/playlists/1/items","type":"playlist","title":"Smart","smart":true,"readOnly":false}"#
        )
        let readOnly = try decodeItem(
            #"{"ratingKey":"2","key":"/playlists/2/items","type":"playlist","title":"Shared","smart":false,"readOnly":true}"#
        )

        await store.loadLibraryProviderCapabilities()

        #expect(store.supportsPlaylistManagement(for: smart))
        #expect(!store.supportsChildManagement(of: smart))
        #expect(!store.supportsPlaylistManagement(for: readOnly))
        #expect(!store.supportsChildManagement(of: readOnly))
    }

    @Test func readOnlyProviderAllowsListingButRefusesPlaylistMutations() async throws {
        let scenario = ReadOnlyPlaylistScenario()
        let store = try makeStore { request in
            try scenario.response(for: request)
        }
        let playlist = try decodeItem(
            #"{"ratingKey":"901","key":"/playlists/901/items","type":"playlist","title":"Shared","smart":false,"readOnly":false}"#
        )

        await store.loadLibraryProviderCapabilities()
        await store.loadPlaylists()

        #expect(!store.supportsPlaylistCreation)
        #expect(!store.supportsPlaylistManagement(for: playlist))
        #expect(store.playlists.map(\.title) == ["Shared"])
        await #expect(throws: PlexBrowserMutationError.self) {
            try await store.renamePlaylist(playlist, to: "Changed")
        }
        #expect(scenario.methodsAndPaths == [
            "GET /media/providers",
            "GET /provider/playlists",
        ])
    }

    private func makeStore(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) throws -> PlexBrowserStore {
        ManagementMockURLProtocol.requestHandler = handler
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [ManagementMockURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)

        let suiteName = "PlexBarTests.collectionPlaylistManagement.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(
                credentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
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
            client: PlexAPIClient(session: session),
            pageSize: 100
        )
    }

    private func makeLibrary() -> PlexLibrary {
        PlexLibrary(
            id: "26",
            title: "Movies",
            type: .movie,
            compositePath: nil,
            artPath: nil,
            thumbPath: nil,
            itemCount: 1,
            secondaryCount: nil,
            secondaryCountLabel: nil,
            updatedAt: nil,
            scannedAt: nil,
            contentChangedAt: nil,
            latestAddedAt: nil,
            latestItemTitle: nil
        )
    }

    private func decodeItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }
}

private final class CollectionManagementScenario: @unchecked Sendable {
    private let lock = NSLock()
    private let canManage: Bool
    private var collectionTitle: String?
    private var recordedMethodsAndPaths: [String] = []

    init(canManage: Bool) {
        self.canManage = canManage
    }

    var methodsAndPaths: [String] {
        lock.withLock { recordedMethodsAndPaths }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        try lock.withLock {
            let url = try #require(request.url)
            recordedMethodsAndPaths.append("\(request.httpMethod ?? "GET") \(url.path)")

            switch (request.httpMethod, url.path) {
            case ("GET", "/media/providers"):
                return try managementResponse(
                    for: request,
                    data: providerData(canManage: canManage)
                )
            case ("POST", "/provider/collections"):
                collectionTitle = queryValue("title", in: request)
                return try managementResponse(for: request, data: collectionData(title: collectionTitle))
            case ("PUT", "/provider/metadata/900"):
                collectionTitle = queryValue("title", in: request)
                return try managementResponse(for: request, data: Data())
            case ("DELETE", "/library/sections/26/collection/900"):
                collectionTitle = nil
                return try managementResponse(for: request, data: Data())
            case ("GET", "/library/sections/26/collections"):
                return try managementResponse(for: request, data: collectionData(title: collectionTitle))
            default:
                Issue.record("Unexpected collection-management request: \(request)")
                return try managementResponse(for: request, data: Data(#"{"MediaContainer":{}}"#.utf8))
            }
        }
    }
}

private final class MissingCollectionFeatureScenario: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedMethodsAndPaths: [String] = []

    var methodsAndPaths: [String] {
        lock.withLock { recordedMethodsAndPaths }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        try lock.withLock {
            let url = try #require(request.url)
            recordedMethodsAndPaths.append("\(request.httpMethod ?? "GET") \(url.path)")
            guard request.httpMethod == "GET", url.path == "/media/providers" else {
                Issue.record("Unexpected incomplete-provider request: \(request)")
                return try managementResponse(for: request, data: Data())
            }
            return try managementResponse(
                for: request,
                data: providerData(canManage: true, includeCollectionFeatures: false)
            )
        }
    }
}

private final class PlaylistChildrenManagementScenario: @unchecked Sendable {
    private let lock = NSLock()
    private var orderedIDs = ["1001", "1002", "1003"]
    private var records: [String] = []

    var methodsPathsAndQueries: [String] {
        lock.withLock { records }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        try lock.withLock {
            let url = try #require(request.url)
            let query = url.query.map { "?\($0)" } ?? ""
            records.append("\(request.httpMethod ?? "GET") \(url.path)\(query)")

            switch (request.httpMethod, url.path) {
            case ("GET", "/media/providers"):
                return try managementResponse(for: request, data: providerData(canManage: true))
            case ("GET", "/playlists/901/items"):
                return try managementResponse(for: request, data: playlistChildrenData(ids: orderedIDs))
            case ("PUT", "/provider/playlists/901/items/1002/move"):
                orderedIDs = ["1001", "1003", "1002"]
                return try managementResponse(for: request, data: Data())
            case ("DELETE", "/provider/playlists/901/items/1002"):
                orderedIDs.removeAll { $0 == "1002" }
                return try managementResponse(for: request, data: Data())
            default:
                Issue.record("Unexpected playlist-management request: \(request)")
                return try managementResponse(for: request, data: Data(#"{"MediaContainer":{}}"#.utf8))
            }
        }
    }
}

private final class ReadOnlyPlaylistScenario: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String] = []

    var methodsAndPaths: [String] {
        lock.withLock { records }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        try lock.withLock {
            let url = try #require(request.url)
            records.append("\(request.httpMethod ?? "GET") \(url.path)")
            switch (request.httpMethod, url.path) {
            case ("GET", "/media/providers"):
                return try managementResponse(
                    for: request,
                    data: providerData(canManage: true, playlistReadOnly: true)
                )
            case ("GET", "/provider/playlists"):
                return try managementResponse(for: request, data: readOnlyPlaylistData())
            default:
                Issue.record("Unexpected read-only playlist request: \(request)")
                return try managementResponse(for: request, data: Data())
            }
        }
    }
}

private final class CollectionCreateAndAddFailureScenario: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String] = []

    var methodsAndPaths: [String] {
        lock.withLock { records }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        try lock.withLock {
            let url = try #require(request.url)
            records.append("\(request.httpMethod ?? "GET") \(url.path)")

            switch (request.httpMethod, url.path) {
            case ("GET", "/media/providers"):
                return try managementResponse(for: request, data: providerData(canManage: true))
            case ("POST", "/provider/collections"),
                 ("GET", "/library/sections/26/collections"):
                return try managementResponse(
                    for: request,
                    data: collectionData(title: "Cary Grant")
                )
            case ("PUT", "/provider/collections/900/items"):
                return try managementResponse(for: request, statusCode: 500, data: Data())
            default:
                Issue.record("Unexpected create-and-add request: \(request)")
                return try managementResponse(for: request, data: Data())
            }
        }
    }
}

private final class CollectionAddRefreshFailureScenario: @unchecked Sendable {
    private let lock = NSLock()
    private var collectionLoadCount = 0
    private var recordedAddRequestCount = 0

    var addRequestCount: Int {
        lock.withLock { recordedAddRequestCount }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        try lock.withLock {
            let url = try #require(request.url)

            switch (request.httpMethod, url.path) {
            case ("GET", "/media/providers"):
                return try managementResponse(for: request, data: providerData(canManage: true))
            case ("GET", "/library/sections/26/collections"):
                collectionLoadCount += 1
                if collectionLoadCount == 1 {
                    return try managementResponse(
                        for: request,
                        data: collectionData(title: "Favorites")
                    )
                }
                return try managementResponse(for: request, statusCode: 500, data: Data())
            case ("PUT", "/provider/collections/900/items"):
                recordedAddRequestCount += 1
                return try managementResponse(for: request, data: Data())
            case ("GET", "/library/collections/900/items"):
                return try managementResponse(for: request, statusCode: 500, data: Data())
            default:
                Issue.record("Unexpected add-and-refresh request: \(request)")
                return try managementResponse(for: request, data: Data())
            }
        }
    }
}

private final class ManagementMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

private func managementResponse(
    for request: URLRequest,
    statusCode: Int = 200,
    data: Data
) throws -> (HTTPURLResponse, Data) {
    let response = try #require(HTTPURLResponse(
        url: request.url!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["X-Plex-Container-Total-Size": "3"]
    ))
    return (response, data)
}

private func emptyResponse(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    try managementResponse(for: request, data: Data(#"{"MediaContainer":{}}"#.utf8))
}

private func providerData(
    canManage: Bool,
    playlistReadOnly: Bool = false,
    includeCollectionFeatures: Bool = true
) -> Data {
    if canManage {
        let collectionFeatures = includeCollectionFeatures
            ? #",{"type":"collection","key":"/provider/collections?source=library"},{"type":"metadata","key":"/provider/metadata?source=library"}"#
            : ""
        return Data(
            #"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"timeline","key":"/timeline","scrobbleKey":"/played","unscrobbleKey":"/unplayed"}\#(collectionFeatures),{"type":"playlist","key":"/provider/playlists?source=library","readOnly":\#(playlistReadOnly)},{"type":"manage"}]}]}}"#.utf8
        )
    }
    return Data(
        #"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"timeline","key":"/timeline","scrobbleKey":"/played","unscrobbleKey":"/unplayed"},{"type":"playlist","key":"/provider/playlists?source=library","readOnly":\#(playlistReadOnly)}]}]}}"#.utf8
    )
}

private func readOnlyPlaylistData() -> Data {
    Data(
        #"{"MediaContainer":{"Metadata":[{"ratingKey":"901","key":"/playlists/901/items","type":"playlist","title":"Shared","smart":false,"readOnly":false}]}}"#.utf8
    )
}

private func collectionData(title: String?) throws -> Data {
    guard let title else {
        return Data(#"{"MediaContainer":{"Metadata":[]}}"#.utf8)
    }
    return try JSONSerialization.data(withJSONObject: [
        "MediaContainer": [
            "Metadata": [[
                "ratingKey": "900",
                "key": "/library/collections/900/items",
                "type": "collection",
                "title": title,
                "smart": false,
            ]],
        ],
    ])
}

private func playlistChildrenData(ids: [String]) throws -> Data {
    let metadata: [[String: Any]] = ids.enumerated().map { index, id in
        [
            "ratingKey": String(index + 1),
            "playlistItemID": id,
            "type": "movie",
            "title": "Item \(id)",
        ]
    }
    return try JSONSerialization.data(withJSONObject: [
        "MediaContainer": ["Metadata": metadata],
    ])
}

private func queryValue(_ name: String, in request: URLRequest) -> String? {
    request.url
        .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        .flatMap(\.queryItems)?
        .first(where: { $0.name == name })?
        .value
}
