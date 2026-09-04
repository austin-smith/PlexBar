import Foundation
import Observation

@MainActor
@Observable
final class PlexLibrarySearchStore {
    var text = ""
    private(set) var displayedQuery = ""
    private(set) var pendingQuery: String?
    private(set) var selectedOptions: PlexLibraryBrowseOptions = .default
    private(set) var displayedOptions: PlexLibraryBrowseOptions = .default
    private(set) var pendingOptions: PlexLibraryBrowseOptions?

    private let debounceDuration: Duration

    init(debounceDuration: Duration = .milliseconds(300)) {
        self.debounceDuration = debounceDuration
    }

    var normalizedQuery: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool {
        pendingQuery != nil
    }

    var isUpdating: Bool {
        isSearching
    }

    func selectSort(_ sort: PlexLibrarySortDefinition?) {
        selectedOptions.sort = sort?.selection()
    }

    func selectSortDirection(
        _ direction: PlexLibrarySortDirection,
        definition: PlexLibrarySortDefinition
    ) {
        selectedOptions.sort = definition.selection(direction: direction)
    }

    func isBooleanFilterEnabled(_ filter: PlexLibraryFilterDefinition) -> Bool {
        selectedOptions.enabledBooleanFilterIDs.contains(filter.id)
    }

    func setBooleanFilter(_ filter: PlexLibraryFilterDefinition, isEnabled: Bool) {
        if isEnabled {
            selectedOptions.enabledBooleanFilterIDs.insert(filter.id)
        } else {
            selectedOptions.enabledBooleanFilterIDs.remove(filter.id)
        }
    }

    func selectedValues(for filter: PlexLibraryFilterDefinition) -> [PlexLibraryFilterValue] {
        selectedOptions.valueSelections(for: filter.id)
    }

    func setSelectedValues(
        _ values: [PlexLibraryFilterValue],
        for filter: PlexLibraryFilterDefinition
    ) {
        selectedOptions.setValueSelections(values, for: filter.id)
    }

    func selectedValueCount(for filter: PlexLibraryFilterDefinition) -> Int {
        selectedOptions.valueSelections(for: filter.id).count
    }

    var hasSelectedFilters: Bool {
        selectedOptions.hasFilters
    }

    func clearFilters() {
        selectedOptions.enabledBooleanFilterIDs = []
        selectedOptions.valueFilterSelections = []
    }

    func update(load: (String) async -> Void) async {
        await update { query, _ in
            await load(query)
        }
    }

    func update(load: (String, PlexLibraryBrowseOptions) async -> Void) async {
        let requestedQuery = normalizedQuery
        let requestedOptions = selectedOptions
        let tracksSearchProgress = requestedQuery != displayedQuery
            || requestedOptions != displayedOptions

        if tracksSearchProgress {
            pendingQuery = requestedQuery
            pendingOptions = requestedOptions
        } else {
            pendingQuery = nil
            pendingOptions = nil
        }
        defer {
            if tracksSearchProgress,
               pendingQuery == requestedQuery,
               pendingOptions == requestedOptions {
                pendingQuery = nil
                pendingOptions = nil
            }
        }

        if requestedQuery != displayedQuery, !requestedQuery.isEmpty {
            try? await Task.sleep(for: debounceDuration)
        }
        guard !Task.isCancelled else {
            return
        }

        await load(requestedQuery, requestedOptions)
        guard !Task.isCancelled,
              normalizedQuery == requestedQuery,
              selectedOptions == requestedOptions else {
            return
        }
        displayedQuery = requestedQuery
        displayedOptions = requestedOptions
    }
}
