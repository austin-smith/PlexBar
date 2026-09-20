import PlexClientKit
import Foundation
import PlexModels
import Testing
@testable import PlexBar

@MainActor
struct PlexPaletteSearchTests {
    @Test func contentOwnsDefaultSelectionAndLateResultsPreserveExplicitSelection() async throws {
        let gate = PaletteSearchGate()
        let store = configuredStore(gate: gate)
        store.updateCommands([.init(id: .settings, title: "Open Settings", systemImage: "gear", group: .app)])
        store.present()
        store.query = "settings"
        #expect(store.isSearching)
        #expect(store.selectedID == nil)
        await gate.waitForRequest("settings")
        let hubs = try fixture(title: "Settings", key: "1")
        await gate.complete("settings", hubs: hubs)
        await settled(store)
        #expect(store.selectedID == .media("1"))

        store.query = "open"
        await gate.waitForRequest("open")
        store.select(.command(.settings))
        await gate.complete("open", hubs: try fixture(title: "Open", key: "2"))
        await settled(store)
        #expect(store.selectedID == .command(.settings))
    }

    @Test func supersededAndDismissedRequestsCannotPublishResults() async throws {
        let gate = PaletteSearchGate()
        let store = configuredStore(gate: gate)
        store.present()
        store.query = "old"
        await gate.waitForRequest("old")
        store.query = "new"
        await gate.waitForRequest("new")
        await gate.complete("new", hubs: try fixture(title: "New", key: "2"))
        await settled(store)
        await gate.complete("old", hubs: try fixture(title: "Old", key: "1"))
        #expect(store.hubs.first?.metadata.first?.title == "New")
        store.query = "dismissed"
        await gate.waitForRequest("dismissed")
        store.dismiss()
        await gate.complete("dismissed", hubs: try fixture(title: "Dismissed", key: "3"))
        store.present()
        #expect(store.query.isEmpty)
        #expect(store.hubs.isEmpty)
        #expect(!store.isSearching)
    }

    @Test func accountChangeClearsRecentsAndPendingWork() async throws {
        let gate = PaletteSearchGate()
        let store = configuredStore(gate: gate)
        let item = try #require(fixture(title: "Movie", key: "1").first?.metadata.first)
        store.remember(item)
        store.present()
        store.query = "Movie"
        await gate.waitForRequest("Movie")
        store.configure(scope: "another-user", canSearch: true, suggestions: [], libraries: [], downloads: []) { _ in [] }
        await gate.complete("Movie", hubs: try fixture(title: "Movie", key: "1"))
        #expect(!store.isPresented)
        #expect(store.recentItems.isEmpty)
        store.present()
        #expect(store.hubs.isEmpty)
    }

    @Test func failureIsDistinctFromNoMatchesAndOneCharacterQueriesAreSent() async throws {
        let gate = PaletteSearchGate()
        let store = configuredStore(gate: gate)
        store.present()
        store.query = "π"
        await gate.waitForRequest("π")
        await gate.fail("π")
        await settled(store)
        #expect(store.searchError != nil)
        #expect(store.hubs.isEmpty)
        store.query = "x"
        await gate.waitForRequest("x")
        await gate.complete("x", hubs: [])
        await settled(store)
        #expect(store.searchError == nil)
        #expect(store.hubs.isEmpty)
    }

    @Test func exactCommandsLeadPartialLibraryMatchesWithoutHidingContent() async throws {
        let gate = PaletteSearchGate()
        let store = configuredStore(gate: gate)
        store.updateCommands([.init(id: .settings, title: "Open Settings", systemImage: "gear", group: .app,
                                    keywords: ["settings", "preferences"])])
        store.present()
        store.query = "settings"
        #expect(store.results.first?.id == .command(.settings))
        #expect(store.hasMatchingResults)
        #expect(store.selectedID == nil)
        await gate.waitForRequest("settings")
        await gate.complete("settings", hubs: try fixture(title: "The Settings", key: "1"))
        await settled(store)
        #expect(store.selectedID == .command(.settings))
        #expect(store.results.map(\.id) == [.command(.settings), .media("1"), .allResults])
        #expect(store.results.map(\.group) == ["Commands", "Library", "Search"])
        store.dismiss()
        store.present()
        #expect(store.query.isEmpty)
    }

    @Test func exactLibraryTitlesLeadEvenWhenACommandAliasMatches() async throws {
        let gate = PaletteSearchGate()
        let store = configuredStore(gate: gate)
        store.updateCommands([.init(id: .navigate(.home), title: "Open Home", systemImage: "house", group: .navigation,
                                    keywords: ["home"])])
        store.present()
        store.query = "home"
        await gate.waitForRequest("home")
        await gate.complete("home", hubs: try fixture(title: "Home", key: "1"))
        await settled(store)
        #expect(store.results.map(\.id) == [.media("1"), .command(.navigate(.home)), .allResults])
        #expect(store.selectedID == .media("1"))
    }

    @Test func mixedSearchBoundsLibraryPreviewAndKeepsEveryMatchingCommandReachable() async throws {
        let gate = PaletteSearchGate()
        let store = configuredStore(gate: gate)
        let commands: [PlexPaletteCommand] = (1...7).map { index in
            .init(id: .navigate(.library(String(index))), title: "Open Library \(index)", systemImage: "film", group: .libraries)
        }
        store.updateCommands(commands)
        store.present()
        store.query = "open"
        await gate.waitForRequest("open")
        var hub = try #require(fixture(title: "Open One", key: "1").first)
        hub.metadata = try (1...8).map { index in
            try #require(fixture(title: "Open Movie \(index)", key: String(index)).first?.metadata.first)
        }
        var secondHub = try JSONDecoder().decode(PlexHub.self, from: Data(
            #"{"hubIdentifier":"other.movies","title":"Other Movies","Metadata":[]}"#.utf8
        ))
        secondHub.metadata = Array(hub.metadata.suffix(4))
        hub.metadata = Array(hub.metadata.prefix(4))
        #expect(PlexPaletteResult.mediaResults(hubs: [hub, secondHub], query: "open", libraries: [], downloads: []).count == 8)
        await gate.complete("open", hubs: [hub, secondHub])
        await settled(store)
        let commandIDs = commands.map { PlexPaletteResult.ID.command($0.id) }
        #expect(Array(store.results.prefix(4)).map(\.id) == (1...4).map { .media(String($0)) })
        #expect(Array(store.results.dropFirst(4).prefix(7)).map(\.id) == commandIDs)
        #expect(store.results.last?.id == .allResults)
    }

    @Test(arguments: ["/", "AC/DC", "> settings"])
    func punctuationIsAlwaysLiteralSearchText(_ query: String) async throws {
        let gate = PaletteSearchGate()
        let store = configuredStore(gate: gate)
        store.present()
        store.query = query
        await gate.waitForRequest(query)
        #expect(store.searchQuery == query)
        await gate.complete(query, hubs: [])
        await settled(store)
        #expect(!store.hasMatchingResults)
        #expect(store.searchError == nil)
    }

    @Test func rankingPromotesExactTitlesDeduplicatesIdentityAndKeepsDistinctCopies() throws {
        let hubs = try JSONDecoder().decode(PlexHubEnvelope.self, from: Data(#"""
        {"MediaContainer":{"Hub":[
          {"hubIdentifier":"movie","title":"Movies","Metadata":[
            {"ratingKey":"1","title":"Dune Part Two","type":"movie","year":2024},
            {"ratingKey":"2","title":"Dune","type":"movie","year":2021,"librarySectionTitle":"Movies"},
            {"ratingKey":"3","title":"Dune","type":"movie","year":1984,"librarySectionTitle":"Classics"}]},
          {"hubIdentifier":"related","title":"Related","Metadata":[
            {"ratingKey":"2","title":"Dune","type":"movie"},
            {"ratingKey":"4","title":"Dune","type":"album","parentTitle":"Frank Herbert","librarySectionTitle":"Audiobooks"}]}]}}
        """#.utf8)).mediaContainer.hubs
        let results = PlexPaletteResult.mediaResults(hubs: hubs, query: "dune", libraries: [], downloads: [])
        #expect(results.map(\.id) == [.media("2"), .media("3"), .media("4"), .media("1")])
        #expect(results[0].group == "Top Results")
        #expect(results[0].subtitle?.contains("2021") == true)
        #expect(results[2].subtitle?.contains("Audiobooks") == true)
        #expect(!results[2].canPlay)
        #expect(results[0].canPlay)
    }

    @Test func playbackFailureKeepsSearchOpenAndCancellationCannotStartPlayback() async throws {
        let gate = PaletteSearchGate()
        let item = try #require(fixture(title: "Movie", key: "1").first?.metadata.first)
        let store = PlexCommandPaletteStore(debounce: .zero)
        store.configure(scope: "account", canSearch: true, suggestions: [item], libraries: [], downloads: []) { _ in [] }
        store.present()
        let result = try #require(store.selectedResult)
        var starts = 0
        store.preparePlayback(result, prepare: {
            _ = try await gate.search("failure")
            throw URLError(.cannotConnectToHost)
        }, present: { _ in starts += 1 })
        await gate.waitForRequest("failure")
        await gate.complete("failure", hubs: [])
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while store.isPreparingPlayback, ContinuousClock.now < deadline { await Task.yield() }
        #expect(store.actionError != nil)
        #expect(store.isPresented)
        #expect(starts == 0)
        let presentation = PlexPlaybackPresentation(
            item: item,
            plan: PlexPlaybackPlan(url: URL(fileURLWithPath: "/tmp/search-test.mp4"), method: .directPlay,
                                   mediaKind: .video, sessionIdentifier: "search-test", ratingKey: "1",
                                   duration: 60, startTime: 0, source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
                                   usesServerMediaSelection: false),
            queue: nil, videoQuality: .original
        )
        store.preparePlayback(result, prepare: {
            _ = try await gate.search("cancelled")
            return presentation
        }, present: { _ in starts += 1 })
        await gate.waitForRequest("cancelled")
        store.dismiss()
        await gate.complete("cancelled", hubs: [])
        store.present()
        #expect(starts == 0)
        #expect(!store.isPreparingPlayback)
    }

    @Test func malformedMediaDirectorySurfacesItsError() {
        let data = Data(#"{"MediaContainer":{"Hub":[{"hubIdentifier":"movie","title":"Movies","Directory":[{"ratingKey":"1","type":"movie","title":{}}]}]}}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PlexHubEnvelope.self, from: data)
        }
    }

    @Test func adoptingSearchCommitsSnapshotAndResetsOldNavigation() throws {
        let store = PlexGlobalSearchStore()
        let hubs = try fixture(title: "Charade", key: "1")
        store.text = "old"
        store.navigationPath = [.media(PlexMediaRoute(ratingKey: "old")!)]
        store.adopt(query: "Charade", hubs: hubs, destination: .media(PlexMediaRoute(ratingKey: "1")!))
        #expect(store.text == "Charade")
        #expect(store.displayedQuery == "Charade")
        #expect(store.visibleHubs == hubs)
        #expect(store.navigationPath.isEmpty)
        #expect(store.hasSearched)
        #expect(store.pendingDestination == .media(PlexMediaRoute(ratingKey: "1")!))
        store.openPendingDestination()
        #expect(store.navigationPath == [.media(PlexMediaRoute(ratingKey: "1")!)])
        #expect(store.pendingDestination == nil)
        store.openPendingDestination()
        #expect(store.navigationPath.count == 1)
    }

    private func configuredStore(gate: PaletteSearchGate) -> PlexCommandPaletteStore {
        let store = PlexCommandPaletteStore(debounce: .zero)
        store.configure(scope: "account-server", canSearch: true, suggestions: [], libraries: [], downloads: []) {
            try await gate.search($0)
        }
        return store
    }

    private func fixture(title: String, key: String) throws -> [PlexHub] {
        let data = try JSONSerialization.data(withJSONObject: ["MediaContainer": ["Hub": [
            ["hubIdentifier": "movie", "title": "Movies", "Metadata": [
                ["ratingKey": key, "title": title, "type": "movie"]
            ]]
        ]]])
        return try JSONDecoder().decode(PlexHubEnvelope.self, from: data).mediaContainer.hubs
    }

    private func settled(_ store: PlexCommandPaletteStore) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while store.isSearching, ContinuousClock.now < deadline { await Task.yield() }
        #expect(!store.isSearching)
    }
}

private actor PaletteSearchGate {
    private var pending: [String: CheckedContinuation<[PlexHub], Error>] = [:]
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private(set) var requestCount = 0

    func search(_ query: String) async throws -> [PlexHub] {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[query] = continuation
            waiters.removeValue(forKey: query)?.resume()
        }
    }

    func waitForRequest(_ query: String) async {
        if pending[query] != nil { return }
        await withCheckedContinuation { waiters[query] = $0 }
    }

    func complete(_ query: String, hubs: [PlexHub]) { pending.removeValue(forKey: query)?.resume(returning: hubs) }
    func fail(_ query: String) { pending.removeValue(forKey: query)?.resume(throwing: URLError(.notConnectedToInternet)) }
}
