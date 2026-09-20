@testable import PlexClientKit
import Foundation
import Testing
@testable import PlexBar

@MainActor
struct PlexLibrarySearchStoreTests {
    @Test func searchRemainsInProgressUntilTheServerLoadCompletes() async {
        let store = PlexLibrarySearchStore(debounceDuration: .zero)
        let gate = SearchLoadGate()
        store.text = "Alien"

        let update = Task {
            await store.update { query in
                #expect(query == "Alien")
                await gate.suspendLoad()
            }
        }

        await gate.waitUntilLoadStarts()
        #expect(store.isSearching)
        #expect(store.pendingQuery == "Alien")
        #expect(store.displayedQuery.isEmpty)

        await gate.finishLoad()
        await update.value

        #expect(!store.isSearching)
        #expect(store.displayedQuery == "Alien")
    }

    @Test func clearingSearchReportsProgressAndKeepsTheDisplayedResultsStable() async {
        let store = PlexLibrarySearchStore(debounceDuration: .zero)
        store.text = "Alien"
        await store.update { _ in }

        let gate = SearchLoadGate()
        store.text = ""
        let update = Task {
            await store.update { query in
                #expect(query.isEmpty)
                await gate.suspendLoad()
            }
        }

        await gate.waitUntilLoadStarts()
        #expect(store.isSearching)
        #expect(store.pendingQuery == "")
        #expect(store.displayedQuery == "Alien")

        await gate.finishLoad()
        await update.value

        #expect(!store.isSearching)
        #expect(store.displayedQuery.isEmpty)
    }

    @Test func aSupersededSearchCannotReplaceNewerResults() async {
        let store = PlexLibrarySearchStore(debounceDuration: .zero)
        let firstLoad = SearchLoadGate()
        store.text = "Alien"

        let firstUpdate = Task {
            await store.update { _ in
                await firstLoad.suspendLoad()
            }
        }
        await firstLoad.waitUntilLoadStarts()

        store.text = "Aliens"
        await store.update { query in
            #expect(query == "Aliens")
        }
        #expect(store.displayedQuery == "Aliens")

        await firstLoad.finishLoad()
        await firstUpdate.value

        #expect(store.displayedQuery == "Aliens")
        #expect(!store.isSearching)
    }

    @Test func browseOptionChangeKeepsDisplayedResultsStableUntilLoadCompletes() async throws {
        let store = PlexLibrarySearchStore(debounceDuration: .zero)
        let sort = try JSONDecoder().decode(
            PlexLibrarySortDefinition.self,
            from: Data(
                #"{"key":"addedAt","descKey":"addedAt:desc","title":"Date Added","defaultDirection":"desc"}"#.utf8
            )
        )
        store.selectSort(sort)
        let gate = SearchLoadGate()

        let update = Task {
            await store.update { query, options in
                #expect(query.isEmpty)
                #expect(options.sort?.queryValue == "addedAt:desc")
                await gate.suspendLoad()
            }
        }

        await gate.waitUntilLoadStarts()
        #expect(store.isUpdating)
        #expect(store.displayedOptions == .default)
        #expect(store.pendingOptions?.sort?.queryValue == "addedAt:desc")

        await gate.finishLoad()
        await update.value

        #expect(!store.isUpdating)
        #expect(store.displayedOptions.sort?.queryValue == "addedAt:desc")
    }

    @Test func supersededBrowseOptionsCannotReplaceNewerResults() async throws {
        let store = PlexLibrarySearchStore(debounceDuration: .zero)
        let definitionData = Data(
            #"{"key":"addedAt","descKey":"addedAt:desc","title":"Date Added","defaultDirection":"desc"}"#.utf8
        )
        let sort = try JSONDecoder().decode(PlexLibrarySortDefinition.self, from: definitionData)
        let firstLoad = SearchLoadGate()
        store.selectSort(sort)

        let firstUpdate = Task {
            await store.update { _, _ in
                await firstLoad.suspendLoad()
            }
        }
        await firstLoad.waitUntilLoadStarts()

        store.selectSortDirection(.ascending, definition: sort)
        await store.update { _, options in
            #expect(options.sort?.queryValue == "addedAt")
        }

        await firstLoad.finishLoad()
        await firstUpdate.value

        #expect(store.displayedOptions.sort?.queryValue == "addedAt")
        #expect(!store.isUpdating)
    }

    @Test func valueFilterChangeKeepsDisplayedResultsStableUntilLoadCompletes() async throws {
        let store = PlexLibrarySearchStore(debounceDuration: .zero)
        let filter = try JSONDecoder().decode(
            PlexLibraryFilterDefinition.self,
            from: Data(
                #"{"filter":"genre","filterType":"string","key":"/library/sections/2/genre","title":"Genre"}"#.utf8
            )
        )
        let action = PlexLibraryFilterValue(
            filterID: "genre",
            queryName: "genre",
            queryValue: "190",
            title: "Action"
        )
        store.setSelectedValues([action], for: filter)
        let gate = SearchLoadGate()

        let update = Task {
            await store.update { query, options in
                #expect(query.isEmpty)
                #expect(options.valueSelections(for: "genre") == [action])
                await gate.suspendLoad()
            }
        }

        await gate.waitUntilLoadStarts()
        #expect(store.isUpdating)
        #expect(store.displayedOptions.valueFilterSelections.isEmpty)
        #expect(store.pendingOptions?.valueSelections(for: "genre") == [action])

        await gate.finishLoad()
        await update.value

        #expect(!store.isUpdating)
        #expect(store.displayedOptions.valueSelections(for: "genre") == [action])
    }

    @Test func clearFiltersRemovesBooleanAndValueSelectionsTogether() throws {
        let store = PlexLibrarySearchStore(debounceDuration: .zero)
        let filter = try JSONDecoder().decode(
            PlexLibraryFilterDefinition.self,
            from: Data(
                #"{"filter":"genre","filterType":"string","key":"/library/sections/2/genre","title":"Genre"}"#.utf8
            )
        )
        store.setBooleanFilter(
            try JSONDecoder().decode(
                PlexLibraryFilterDefinition.self,
                from: Data(
                    #"{"filter":"unwatched","filterType":"boolean","key":"/library/sections/2/unwatched","title":"Unwatched"}"#.utf8
                )
            ),
            isEnabled: true
        )
        store.setSelectedValues([
            PlexLibraryFilterValue(
                filterID: "genre",
                queryName: "genre",
                queryValue: "190",
                title: "Action"
            )
        ], for: filter)

        #expect(store.hasSelectedFilters)
        store.clearFilters()
        #expect(!store.hasSelectedFilters)
    }
}

private actor SearchLoadGate {
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
