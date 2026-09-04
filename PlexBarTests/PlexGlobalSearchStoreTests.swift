import Foundation
import Testing
@testable import PlexBar

@MainActor
struct PlexGlobalSearchStoreTests {
    @Test func keepsDisplayedHubsVisibleUntilReplacementSearchCompletes() async throws {
        let store = PlexGlobalSearchStore(debounceDuration: .zero)
        let alienHubs = try hubs(title: "Alien")
        let arrivalHubs = try hubs(title: "Arrival")
        store.text = "Alien"
        await store.update { _ in alienHubs }

        let gate = GlobalSearchLoadGate()
        store.text = "Arrival"
        let update = Task {
            await store.update { query in
                #expect(query == "Arrival")
                await gate.suspendLoad()
                return arrivalHubs
            }
        }

        await gate.waitUntilLoadStarts()
        #expect(store.isSearching)
        #expect(store.pendingQuery == "Arrival")
        #expect(store.displayedQuery == "Alien")
        #expect(store.visibleHubs.flatMap(\.metadata).map(\.title) == ["Alien"])

        await gate.finishLoad()
        await update.value

        #expect(!store.isSearching)
        #expect(store.displayedQuery == "Arrival")
        #expect(store.visibleHubs.flatMap(\.metadata).map(\.title) == ["Arrival"])
    }

    @Test func supersededSearchCannotReplaceNewerResults() async throws {
        let store = PlexGlobalSearchStore(debounceDuration: .zero)
        let firstHubs = try hubs(title: "Alien")
        let secondHubs = try hubs(title: "Aliens")
        let gate = GlobalSearchLoadGate()
        store.text = "Alien"

        let firstUpdate = Task {
            await store.update { _ in
                await gate.suspendLoad()
                return firstHubs
            }
        }
        await gate.waitUntilLoadStarts()

        store.text = "Aliens"
        await store.update { query in
            #expect(query == "Aliens")
            return secondHubs
        }
        #expect(store.displayedQuery == "Aliens")

        await gate.finishLoad()
        await firstUpdate.value

        #expect(store.displayedQuery == "Aliens")
        #expect(store.visibleHubs.flatMap(\.metadata).map(\.title) == ["Aliens"])
        #expect(!store.isSearching)
    }

    @Test func failedReplacementKeepsExistingResultsAndSurfacesTheError() async throws {
        let store = PlexGlobalSearchStore(debounceDuration: .zero)
        let existingHubs = try hubs(title: "Alien")
        store.text = "Alien"
        await store.update { _ in existingHubs }

        store.text = "Arrival"
        await store.update { _ in
            throw PlexAPIError.invalidResponse
        }

        #expect(store.displayedQuery == "Alien")
        #expect(store.visibleHubs.flatMap(\.metadata).map(\.title) == ["Alien"])
        #expect(store.errorMessage != nil)
        #expect(!store.isSearching)
    }

    @Test func clearingQueryResetsResultsErrorsAndNavigation() async throws {
        let store = PlexGlobalSearchStore(debounceDuration: .zero)
        store.text = "Alien"
        await store.update { _ in try hubs(title: "Alien") }
        let item = try #require(store.hubs.first?.metadata.first)
        store.navigationPath = [.media(PlexMediaRoute(item: item))]

        store.text = ""
        await store.update { _ in
            Issue.record("Clearing search must not issue a server request")
            return []
        }

        #expect(store.text.isEmpty)
        #expect(store.displayedQuery.isEmpty)
        #expect(store.hubs.isEmpty)
        #expect(store.navigationPath.isEmpty)
        #expect(!store.hasSearched)
        #expect(store.errorMessage == nil)
    }

    @Test func searchHubRouteRequiresAndMatchesTheExactReturnedKeyAndQuery() throws {
        let hub = try #require(pagedHubs(query: "Alien").first)
        let route = try #require(PlexSearchHubRoute(hub: hub, query: "Alien"))

        #expect(route.hubKey == "/hubs/search?query=Alien&type=1")
        #expect(route.matches(hub, query: "Alien"))
        #expect(!route.matches(hub, query: "Arrival"))

        let hubWithoutKey = try #require(hubs(title: "Alien").first)
        #expect(PlexSearchHubRoute(hub: hubWithoutKey, query: "Alien") == nil)
    }

    @Test func showAllLoadsAndPaginatesUsingOnlyTheExactReturnedHubKey() async throws {
        let store = PlexGlobalSearchStore(debounceDuration: .zero, pageSize: 2)
        store.text = "Alien"
        await store.update { _ in try pagedHubs(query: "Alien") }
        let hub = try #require(store.hubs.first)
        var requests: [(path: String, start: Int, size: Int)] = []

        await store.loadItems(in: hub) { path, start, size in
            requests.append((path, start, size))
            return PlexMediaPage(
                items: try [self.item(title: "Alien", ratingKey: "1"), self.item(title: "Aliens", ratingKey: "2")],
                offset: start,
                totalSize: 3
            )
        }

        let lastItem = try #require(store.items(in: hub).last)
        await store.loadMoreItemsIfNeeded(in: hub, currentItem: lastItem) { path, start, size in
            requests.append((path, start, size))
            return PlexMediaPage(
                items: try [self.item(title: "Alien 3", ratingKey: "3")],
                offset: start,
                totalSize: 3
            )
        }

        #expect(requests.map(\.path) == [
            "/hubs/search?query=Alien&type=1",
            "/hubs/search?query=Alien&type=1"
        ])
        #expect(requests.map(\.start) == [0, 2])
        #expect(requests.map(\.size) == [2, 2])
        #expect(store.items(in: hub).map(\.title) == ["Alien", "Aliens", "Alien 3"])
        #expect(!store.hasMoreItems(in: hub))
    }

    @Test func failedShowAllRefreshKeepsExistingItemsAndExposesError() async throws {
        let store = PlexGlobalSearchStore(debounceDuration: .zero)
        store.text = "Alien"
        await store.update { _ in try pagedHubs(query: "Alien") }
        let hub = try #require(store.hubs.first)
        await store.loadItems(in: hub) { _, _, _ in
            PlexMediaPage(
                items: try [self.item(title: "Alien", ratingKey: "1")],
                offset: 0,
                totalSize: 1
            )
        }

        await store.loadItems(in: hub, forceRefresh: true) { _, _, _ in
            throw PlexAPIError.invalidResponse
        }

        #expect(store.items(in: hub).map(\.title) == ["Alien"])
        #expect(store.itemsErrorMessage(in: hub) != nil)
    }

    @Test func successfulReplacementQueryClearsExpandedItemsAndOldNavigation() async throws {
        let store = PlexGlobalSearchStore(debounceDuration: .zero)
        store.text = "Alien"
        await store.update { _ in try pagedHubs(query: "Alien") }
        let alienHub = try #require(store.hubs.first)
        let alienRoute = try #require(PlexSearchHubRoute(hub: alienHub, query: "Alien"))
        store.navigationPath = [.searchHub(alienRoute)]
        await store.loadItems(in: alienHub) { _, _, _ in
            PlexMediaPage(
                items: try [self.item(title: "Alien", ratingKey: "1")],
                offset: 0,
                totalSize: 1
            )
        }

        store.text = "Arrival"
        await store.update { _ in try pagedHubs(query: "Arrival") }

        #expect(store.displayedQuery == "Arrival")
        #expect(store.itemsByHubPath.isEmpty)
        #expect(store.navigationPath.isEmpty)
        #expect(store.hub(for: alienRoute) == nil)
    }

    @Test func inFlightOldQueryPageCannotRepopulateSuccessfulReplacementState() async throws {
        let store = PlexGlobalSearchStore(debounceDuration: .zero)
        store.text = "Alien"
        await store.update { _ in try pagedHubs(query: "Alien") }
        let alienHub = try #require(store.hubs.first)
        let stalePage = PlexMediaPage(
            items: try [item(title: "Alien", ratingKey: "1")],
            offset: 0,
            totalSize: 1
        )
        let gate = GlobalSearchLoadGate()
        let staleLoad = Task {
            await store.loadItems(in: alienHub) { _, _, _ in
                await gate.suspendLoad()
                return stalePage
            }
        }
        await gate.waitUntilLoadStarts()

        store.text = "Arrival"
        await store.update { _ in try pagedHubs(query: "Arrival") }
        await gate.finishLoad()
        await staleLoad.value

        #expect(store.displayedQuery == "Arrival")
        #expect(store.itemsByHubPath.isEmpty)
    }

    @Test func cachedMutationsAlsoUpdateExpandedSearchResults() async throws {
        let store = PlexGlobalSearchStore(debounceDuration: .zero)
        store.text = "Alien"
        await store.update { _ in try pagedHubs(query: "Alien") }
        let hub = try #require(store.hubs.first)
        await store.loadItems(in: hub) { _, _, _ in
            PlexMediaPage(
                items: try [self.item(title: "Alien", ratingKey: "1", viewCount: 0, userRating: 2)],
                offset: 0,
                totalSize: 1
            )
        }

        let refreshed = try item(
            title: "Alien",
            ratingKey: "1",
            viewCount: 1,
            userRating: 9
        )
        store.replaceCachedWatchedState(with: refreshed)
        store.replaceCachedUserRating(with: refreshed)

        let updated = try #require(store.items(in: hub).first)
        #expect(updated.isWatched)
        #expect(updated.userRating == 9)
    }

    private func hubs(title: String) throws -> [PlexHub] {
        let data = Data(#"""
        {
          "MediaContainer": {
            "Hub": [{
              "hubIdentifier": "movie",
              "title": "Movies",
              "type": "movie",
              "Metadata": [{
                "ratingKey": "\#(title.lowercased())",
                "key": "/library/metadata/\#(title.lowercased())",
                "title": "\#(title)",
                "type": "movie"
              }]
            }]
          }
        }
        """#.utf8)
        return try JSONDecoder().decode(PlexHubEnvelope.self, from: data).mediaContainer.hubs
    }

    private func pagedHubs(query: String) throws -> [PlexHub] {
        let data = Data(#"""
        {
          "MediaContainer": {
            "Hub": [{
              "hubIdentifier": "movie",
              "key": "/hubs/search?query=\#(query)&type=1",
              "title": "Movies",
              "type": "movie",
              "size": 1,
              "totalSize": 3,
              "more": true,
              "Metadata": [{
                "ratingKey": "embedded-\#(query.lowercased())",
                "key": "/library/metadata/embedded-\#(query.lowercased())",
                "title": "\#(query)",
                "type": "movie"
              }]
            }]
          }
        }
        """#.utf8)
        return try JSONDecoder().decode(PlexHubEnvelope.self, from: data).mediaContainer.hubs
    }

    private func item(
        title: String,
        ratingKey: String,
        viewCount: Int? = nil,
        userRating: Double? = nil
    ) throws -> PlexMediaItem {
        let viewCountField = viewCount.map { ",\"viewCount\":\($0)" } ?? ""
        let userRatingField = userRating.map { ",\"userRating\":\($0)" } ?? ""
        let data = Data(#"""
        {
          "MediaContainer": {
            "Metadata": [{
              "ratingKey": "\#(ratingKey)",
              "key": "/library/metadata/\#(ratingKey)",
              "title": "\#(title)",
              "type": "movie"
              \#(viewCountField)
              \#(userRatingField)
            }]
          }
        }
        """#.utf8)
        return try #require(
            JSONDecoder().decode(PlexMediaEnvelope.self, from: data).mediaContainer.metadata.first
        )
    }
}

private actor GlobalSearchLoadGate {
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
