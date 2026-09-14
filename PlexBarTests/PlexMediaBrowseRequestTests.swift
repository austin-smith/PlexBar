import PlexModels
import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexMediaBrowseRequestTests {
    @Test func tvBrowseDefinitionAcceptsSeasonsWithoutFilters() async throws {
        let session = makeBrowseMediaMockSession { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            ))
            switch request.url?.path {
            case "/library/sections/4":
                return (response, Data(#"""
                {"MediaContainer":{"Type":[
                    {"key":"/library/sections/4/all?type=2","type":"show","title":"TV Shows","Filter":[],"Sort":[]},
                    {"key":"/library/sections/4/all?type=3","type":"season","title":"Seasons","Sort":[
                        {"default":"asc","defaultDirection":"asc","descKey":"show.titleSort:desc,index","key":"show.titleSort,index","title":"Show"}
                    ]},
                    {"key":"/library/sections/4/all?type=4","type":"episode","title":"Episodes","Filter":[],"Sort":[]}
                ]}}
                """#.utf8))
            case "/library/sections/4/filters":
                return (response, libraryFiltersData())
            case "/library/sections/4/sorts":
                return (response, librarySortsData())
            default:
                Issue.record("Unexpected browse-definition request: \(request)")
                throw URLError(.unsupportedURL)
            }
        }

        let definition = try await PlexAPIClient(session: session).fetchLibraryBrowseDefinition(
            sectionPath: "/library/sections/4",
            contentPath: "/library/sections/4/all",
            using: try configuration
        )

        #expect(definition.types.map(\.type) == ["show", "season", "episode"])
        #expect(definition.booleanFilters.map(\.id) == ["unwatched"])
        let seasons = try definition.selecting("/library/sections/4/all?type=3")
        #expect(seasons.filters.isEmpty)
        #expect(seasons.sorts.map(\.id) == ["show.titleSort,index"])
    }

    @Test func episodeIdentifierIsLimitedToEpisodeMetadata() throws {
        let show = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"7","type":"show","title":"Show","index":"1","year":"2024"}"#.utf8)
        )
        let episode = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(
                #"{"ratingKey":"8","type":"episode","title":"Pilot","index":"2","parentIndex":"1"}"#.utf8
            )
        )

        #expect(show.episodeIdentifier == nil)
        #expect(show.factsLine == "2024")
        #expect(episode.episodeIdentifier == "S1, E2")
    }

    @Test func browsingRuntimeRoundsToMinutesAndOmitsSeconds() throws {
        let episode = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(
                #"{"ratingKey":"8","type":"episode","title":"Episode","duration":5022000}"#.utf8
            )
        )

        let runtime = episode.formattedDuration?
            .replacingOccurrences(of: "\u{202F}", with: " ")

        #expect(runtime == "1 hr 24 min")
        #expect(runtime?.contains("sec") == false)
    }

    @Test func librarySearchUsesServerSideTitleContainsQuery() async throws {
        let capture = RequestCapture()
        let session = makeBrowseMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Plex-Container-Total-Size": "1"]
            ))
            return (response, Data(#"{"MediaContainer":{"Metadata":[]}}"#.utf8))
        }

        _ = try await PlexAPIClient(session: session).fetchMediaPage(
            libraryID: "2",
            using: try configuration,
            start: 0,
            size: 25,
            searchQuery: "Twin Peaks"
        )

        let request = try #require(capture.request)
        let components = try requestComponents(request)
        #expect(components.queryItems?.contains { $0.name == "title" && $0.value == "Twin Peaks" } == true)
        #expect(components.queryItems?.contains { $0.name == "sort" } != true)
    }

    @Test func browseDefinitionUsesTheAdvertisedLibraryRouteAndDocumentedDescriptors() async throws {
        let capture = RequestCapture()
        let session = makeBrowseMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            switch request.url?.path {
            case "/provider/sections/2":
                return (response, Data(#"{"MediaContainer":{"Type":[]}}"#.utf8))
            case "/provider/sections/2/filters":
                return (response, libraryFiltersData())
            case "/provider/sections/2/sorts":
                return (response, librarySortsData())
            default:
                Issue.record("Unexpected browse-definition request: \(request)")
                throw URLError(.unsupportedURL)
            }
        }

        let definition = try await PlexAPIClient(session: session).fetchLibraryBrowseDefinition(
            sectionPath: "/provider/sections/2",
            contentPath: "/provider/sections/2/all?type=1&source=library",
            using: try configuration
        )

        #expect(definition.contentPath == "/provider/sections/2/all?type=1&source=library")
        #expect(definition.booleanFilters.map(\.id) == ["unwatched"])
        #expect(definition.sorts.map(\.title) == ["Name", "Date Added"])
        #expect(definition.sorts.first?.defaultSelectionDirection == .ascending)
        #expect(definition.sorts.last?.selection()?.queryValue == "addedAt:desc")
        #expect(Set(capture.requests.compactMap(\.url?.path)) == [
            "/provider/sections/2",
            "/provider/sections/2/filters",
            "/provider/sections/2/sorts",
        ])
    }

    @Test func browseDefinitionPreservesTheAdvertisedSectionQueryForDescriptors() async throws {
        let capture = RequestCapture()
        let session = makeBrowseMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))

            switch request.url?.path {
            case "/provider/sections/7":
                return (response, Data(#"""
                {"MediaContainer":{"Type":[
                    {"key":"/provider/sections/7/all?type=8&source=library","type":"artist","title":"Artists","Filter":[],"Sort":[]},
                    {"key":"/provider/sections/7/all?type=9&source=library","type":"album","title":"Albums","Filter":[],"Sort":[]}
                ]}}
                """#.utf8))
            case "/provider/sections/7/filters":
                return (response, libraryFiltersData())
            case "/provider/sections/7/sorts":
                return (response, librarySortsData())
            default:
                Issue.record("Unexpected browse-definition request: \(request)")
                throw URLError(.unsupportedURL)
            }
        }

        let definition = try await PlexAPIClient(session: session).fetchLibraryBrowseDefinition(
            sectionPath: "/provider/sections/7?source=library",
            contentPath: "/provider/sections/7/all?type=1&source=library",
            using: try configuration
        )

        #expect(definition.contentPath == "/provider/sections/7/all?type=1&source=library")
        #expect(definition.filters.map(\.id) == ["genre", "unwatched"])
        #expect(definition.sorts.map(\.id) == ["titleSort", "addedAt"])
        #expect(capture.requests.allSatisfy { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            let expected = [URLQueryItem(name: "source", value: "library")]
                + (request.url?.path == "/provider/sections/7"
                    ? [URLQueryItem(name: "includeDetails", value: "1")] : [])
            return query == expected
        })
        let albums = try definition.selecting("/provider/sections/7/all?type=9&source=library")
        #expect(definition.types.map(\.title) == ["Artists", "Albums"])
        #expect(albums.contentPath == "/provider/sections/7/all?type=9&source=library")
        #expect(albums.filters.isEmpty)
        #expect(albums.sorts.isEmpty)
        #expect(throws: PlexAPIError.self) {
            try definition.selecting("/unadvertised/path")
        }
    }

    @Test func filterValuesUseAdvertisedEndpointAndPreserveServerQueryPairs() async throws {
        let capture = RequestCapture()
        let session = makeBrowseMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(#"""
            {
              "MediaContainer": {
                "Directory": [
                  { "id": 190, "filter": "genre=190", "tag": "Action" },
                  { "key": 98, "title": "Adventure" }
                ]
              }
            }
            """#.utf8))
        }
        let filter = try JSONDecoder().decode(
            PlexLibraryFilterDefinition.self,
            from: Data(
                #"{"filter":"genre","filterType":"string","key":"/library/sections/2/genre?type=1","title":"Genre"}"#.utf8
            )
        )

        let values = try await PlexAPIClient(session: session).fetchLibraryFilterValues(
            for: filter,
            using: try configuration
        )

        let components = try requestComponents(try #require(capture.request))
        #expect(components.path == "/library/sections/2/genre")
        #expect(components.queryItems == [URLQueryItem(name: "type", value: "1")])
        #expect(values == [
            PlexLibraryFilterValue(
                filterID: "genre",
                queryName: "genre",
                queryValue: "190",
                title: "Action"
            ),
            PlexLibraryFilterValue(
                filterID: "genre",
                queryName: "genre",
                queryValue: "98",
                title: "Adventure"
            ),
        ])
    }

    @Test func browseRequestPreservesTypeKeyAndUsesExactServerDescriptors() async throws {
        let capture = RequestCapture()
        let session = makeBrowseMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Plex-Container-Total-Size": "0"]
            ))
            return (response, Data(#"{"MediaContainer":{"Metadata":[]}}"#.utf8))
        }
        let sort = try #require(try decodedBrowseDefinition().sorts.last)
        let options = PlexLibraryBrowseOptions(
            sort: sort.selection(direction: .descending),
            enabledBooleanFilterIDs: ["hdr", "unwatched"],
            valueFilterSelections: [
                PlexLibraryFilterValue(
                    filterID: "genre",
                    queryName: "genre",
                    queryValue: "190",
                    title: "Action"
                ),
                PlexLibraryFilterValue(
                    filterID: "genre",
                    queryName: "genre",
                    queryValue: "98",
                    title: "Adventure"
                ),
                PlexLibraryFilterValue(
                    filterID: "year",
                    queryName: "year",
                    queryValue: "2024",
                    title: "2024"
                ),
            ]
        )

        _ = try await PlexAPIClient(session: session).fetchMediaPage(
            contentPath: "/library/sections/2/all?type=1&includeGuids=1&sort=serverDefault",
            using: try configuration,
            start: 0,
            size: 25,
            searchQuery: "Alien",
            browseOptions: options
        )

        let request = try #require(capture.request)
        let queryItems = try requestComponents(request).queryItems ?? []
        #expect(queryItems.filter { $0.name == "sort" } == [
            URLQueryItem(name: "sort", value: "addedAt:desc")
        ])
        #expect(queryItems.contains(URLQueryItem(name: "type", value: "1")))
        #expect(queryItems.contains(URLQueryItem(name: "includeGuids", value: "1")))
        #expect(queryItems.contains(URLQueryItem(name: "title", value: "Alien")))
        #expect(queryItems.contains(URLQueryItem(name: "hdr", value: "1")))
        #expect(queryItems.contains(URLQueryItem(name: "unwatched", value: "1")))
        #expect(queryItems.filter { $0.name == "genre" } == [
            URLQueryItem(name: "genre", value: "190,98")
        ])
        #expect(queryItems.contains(URLQueryItem(name: "year", value: "2024")))
    }

    @Test func sortWithoutServerDescendingKeyDoesNotInventOne() throws {
        let data = Data(#"{"key":"random","title":"Random","defaultDirection":"desc"}"#.utf8)
        let sort = try JSONDecoder().decode(PlexLibrarySortDefinition.self, from: data)

        #expect(sort.selection() == nil)
        #expect(sort.selection(direction: .ascending)?.queryValue == "random")
    }

    @Test func childrenRequestRespectsSkipChildrenAndDecodesHierarchyFields() async throws {
        let capture = RequestCapture()
        let session = makeBrowseMediaMockSession { request in
            capture.record(request)
            return try hierarchyResponse(for: request)
        }
        let show = try JSONDecoder().decode(PlexMediaItem.self, from: skippedSeasonShowData())

        let page = try await PlexAPIClient(session: session).fetchMediaChildren(
            of: show,
            using: try configuration,
            start: 50,
            size: 25
        )

        let request = try #require(capture.request)
        #expect(request.url?.path == "/library/metadata/7/grandchildren")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Start") == "50")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "25")
        #expect(page.items.first?.parentRatingKey == "70")
        #expect(page.items.first?.grandparentRatingKey == "7")
        #expect(page.items.first?.parentThumb == "/library/metadata/70/thumb")
    }

    @Test func skipChildrenPreservesServerQueryItemsWhenSelectingGrandchildren() throws {
        let show = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"7","key":"/library/metadata/7/children?includeGuids=1&excludeAllLeaves=0","type":"show","title":"Show","skipChildren":"1"}"#.utf8)
        )

        let path = try #require(show.childrenPath)
        let components = try #require(URLComponents(string: path))
        #expect(components.path == "/library/metadata/7/grandchildren")
        #expect(components.queryItems == [
            URLQueryItem(name: "includeGuids", value: "1"),
            URLQueryItem(name: "excludeAllLeaves", value: "0"),
        ])
    }

    @Test func photoLibrariesUseThePhotoAlbumPivotForHierarchicalBrowsing() {
        #expect(PlexLibraryType.photo.metadataTypeID == 14)
        #expect(PlexLibraryType.photoAlbum.metadataTypeID == 14)
    }

    @Test func photoAlbumsFollowTheirExactServerReturnedChildrenKey() async throws {
        let capture = RequestCapture()
        let session = makeBrowseMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Plex-Container-Total-Size": "1"]
            ))
            return (response, Data(#"{"MediaContainer":{"Metadata":[]}}"#.utf8))
        }
        let album = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(
                #"{"ratingKey":"44","key":"/library/metadata/44/children?includeRelated=0","type":"photoalbum","title":"Vacation"}"#.utf8
            )
        )

        _ = try await PlexAPIClient(session: session).fetchMediaChildren(
            of: album,
            using: try configuration,
            start: 0,
            size: 50
        )

        let request = try #require(capture.request)
        let components = try requestComponents(request)
        #expect(album.hasChildren)
        #expect(components.path == "/library/metadata/44/children")
        #expect(components.queryItems == [URLQueryItem(name: "includeRelated", value: "0")])
    }

    @Test func returnedPlexKeyPreservesItsQueryItems() async throws {
        let capture = RequestCapture()
        let session = makeBrowseMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(#"{"MediaContainer":{"Metadata":[]}}"#.utf8))
        }
        let album = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"""
            {
              "ratingKey": "265",
              "key": "/library/metadata/265/children?includeGuids=1",
              "type": "album",
              "title": "Mandatory Fun"
            }
            """#.utf8)
        )

        _ = try await PlexAPIClient(session: session).fetchMediaChildren(
            of: album,
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try requestComponents(request)
        #expect(components.queryItems?.contains { $0.name == "includeGuids" && $0.value == "1" } == true)
    }

    @MainActor
    @Test func filterValueCacheIsScopedToTheResolvedServerConnection() async throws {
        let suiteName = "PlexBarTests.filterValueCacheIsScopedToConnection"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let counter = FilterValueRequestCounter()
        let session = makeBrowseMediaMockSession { request in
            counter.record()
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let title = request.url?.host == "plex.remote" ? "Remote" : "Local"
            return (response, Data(#"{"MediaContainer":{"Directory":[{"key":"1","title":"\#(title)"}]}}"#.utf8))
        }
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(
                credentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
            ),
            initialCredentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
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
        let store = PlexBrowserStore(
            connectionStore: connectionStore,
            client: PlexAPIClient(session: session)
        )
        let filter = try JSONDecoder().decode(
            PlexLibraryFilterDefinition.self,
            from: Data(
                #"{"filter":"genre","filterType":"string","key":"/library/sections/2/genre","title":"Genre"}"#.utf8
            )
        )

        await store.loadFilterValues(for: filter)
        await store.loadFilterValues(for: filter)
        #expect(counter.count == 1)
        #expect(store.filterValues(for: filter).map(\.title) == ["Local"])

        connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "server-id",
            url: try #require(URL(string: "https://plex.remote:32400")),
            kind: .remote,
            validatedAt: Date()
        )
        #expect(store.filterValues(for: filter).isEmpty)

        await store.loadFilterValues(for: filter)
        #expect(counter.count == 2)
        #expect(store.filterValues(for: filter).map(\.title) == ["Remote"])

        settings.serverToken = "another-server-token"
        #expect(store.filterValues(for: filter).isEmpty)

        await store.loadFilterValues(for: filter)
        #expect(counter.count == 3)
        #expect(store.filterValues(for: filter).map(\.title) == ["Remote"])
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

    private func requestComponents(_ request: URLRequest) throws -> URLComponents {
        try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
    }
}

private func decodedBrowseDefinition() throws -> PlexLibraryBrowseDefinition {
    let decoded = try JSONDecoder().decode(
        PlexLibraryBrowseEnvelope.self,
        from: libraryBrowseDefinitionData()
    )
    let directory = try #require(decoded.mediaContainer.directories.last)
    let contentPath = try #require(directory.key)
    return PlexLibraryBrowseDefinition(
        contentPath: contentPath,
        filters: directory.filters,
        sorts: directory.sorts
    )
}

private func libraryBrowseDefinitionData() -> Data {
    Data(#"""
    {
      "MediaContainer": {
        "Directory": [
          {
            "key": "/library/sections/2/all?type=2",
            "type": 2,
            "Filter": [],
            "Sort": []
          },
          {
            "key": "/library/sections/2/all?type=1",
            "type": "1",
            "Filter": [
              {
                "filter": "unwatched",
                "filterType": "boolean",
                "key": "/library/sections/2/unwatched",
                "title": "Unwatched"
              },
              {
                "filter": "genre",
                "filterType": "string",
                "key": "/library/sections/2/genre",
                "title": "Genre"
              }
            ],
            "Sort": [
              {
                "default": "asc",
                "defaultDirection": "asc",
                "descKey": "titleSort:desc",
                "key": "titleSort",
                "title": "Name"
              },
              {
                "defaultDirection": "desc",
                "descKey": "addedAt:desc",
                "key": "addedAt",
                "title": "Date Added"
              }
            ]
          }
        ]
      }
    }
    """#.utf8)
}

private func libraryFiltersData() -> Data {
    Data(#"""
    {
      "MediaContainer": {
        "Directory": [
          {
            "filter": "genre",
            "filterType": "string",
            "key": "/library/sections/7/genre",
            "title": "Genre"
          },
          {
            "filter": "unwatched",
            "filterType": "boolean",
            "key": "/library/sections/7/unwatched",
            "title": "Unwatched"
          }
        ]
      }
    }
    """#.utf8)
}

private func librarySortsData() -> Data {
    Data(#"""
    {
      "MediaContainer": {
        "Directory": [
          {
            "default": "asc",
            "defaultDirection": "asc",
            "descKey": "titleSort:desc",
            "key": "titleSort",
            "title": "Name"
          },
          {
            "defaultDirection": "desc",
            "descKey": "addedAt:desc",
            "key": "addedAt",
            "title": "Date Added"
          }
        ]
      }
    }
    """#.utf8)
}

private func hierarchyResponse(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    let response = try #require(HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["X-Plex-Container-Total-Size": "1"]
    ))
    let data = Data(#"""
    {
      "MediaContainer": {
        "Metadata": [{
          "ratingKey": "701",
          "parentRatingKey": 70,
          "grandparentRatingKey": "7",
          "title": "Episode One",
          "type": "episode",
          "index": "1",
          "parentIndex": "1",
          "parentThumb": "/library/metadata/70/thumb",
          "grandparentThumb": "/library/metadata/7/thumb"
        }]
      }
    }
    """#.utf8)
    return (response, data)
}

private func skippedSeasonShowData() -> Data {
    Data(#"""
    {
      "ratingKey": "7",
      "key": "/library/metadata/7/children",
      "type": "show",
      "title": "One Season Show",
      "skipChildren": "1"
    }
    """#.utf8)
}

private func makeBrowseMediaMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    BrowseMediaMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BrowseMediaMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class BrowseMediaMockURLProtocol: URLProtocol, @unchecked Sendable {
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

private final class FilterValueRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func record() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
