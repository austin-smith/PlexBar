import PlexClientKit
import PlexModels
import Foundation
import Observation

@MainActor
@Observable
final class PlexGlobalSearchStore {
    var text = ""
    var navigationPath: [PlexNavigationRoute] = []
    private(set) var pendingDestination: PlexNavigationRoute?
    private(set) var displayedQuery = ""
    private(set) var pendingQuery: String?
    private(set) var hubs: [PlexHub] = []
    private(set) var hasSearched = false
    private(set) var errorMessage: String?
    private(set) var itemsByHubPath: [String: [PlexMediaItem]] = [:]
    private(set) var totalSizesByHubPath: [String: Int] = [:]
    private(set) var loadedHubPaths: Set<String> = []
    private(set) var loadingHubPaths: Set<String> = []
    private(set) var errorMessagesByHubPath: [String: String] = [:]

    private let debounceDuration: Duration
    private let pageSize: Int
    private var requestRevision = 0
    private var expandedContentRevision = 0

    init(
        debounceDuration: Duration = .milliseconds(300),
        pageSize: Int = 100
    ) {
        self.debounceDuration = debounceDuration
        self.pageSize = max(pageSize, 1)
    }

    var normalizedQuery: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var visibleHubs: [PlexHub] {
        hubs.filter { !$0.metadata.isEmpty }
    }

    var isSearching: Bool {
        pendingQuery != nil
    }

    func update(
        forceRefresh: Bool = false,
        load: (String) async throws -> [PlexHub]
    ) async {
        let requestedQuery = normalizedQuery
        requestRevision += 1
        let revision = requestRevision

        guard !requestedQuery.isEmpty else {
            clearContent()
            return
        }

        if !forceRefresh,
           hasSearched,
           displayedQuery == requestedQuery,
           errorMessage == nil {
            return
        }

        pendingQuery = requestedQuery
        errorMessage = nil

        if !forceRefresh, requestedQuery != displayedQuery {
            do {
                try await Task.sleep(for: debounceDuration)
            } catch {
                finishRequest(revision: revision, query: requestedQuery)
                return
            }
        }

        guard requestRevision == revision,
              normalizedQuery == requestedQuery,
              !Task.isCancelled else {
            finishRequest(revision: revision, query: requestedQuery)
            return
        }

        do {
            let loadedHubs = try await load(requestedQuery)
            guard requestRevision == revision,
                  normalizedQuery == requestedQuery,
                  !Task.isCancelled else {
                finishRequest(revision: revision, query: requestedQuery)
                return
            }

            if displayedQuery != requestedQuery {
                navigationPath.removeAll()
                clearExpandedHubContent()
            }
            hubs = loadedHubs.filter { !$0.metadata.isEmpty }
            displayedQuery = requestedQuery
            hasSearched = true
            errorMessage = nil
        } catch {
            guard requestRevision == revision,
                  normalizedQuery == requestedQuery,
                  !Task.isCancelled else {
                finishRequest(revision: revision, query: requestedQuery)
                return
            }

            if hubs.isEmpty {
                displayedQuery = requestedQuery
            }
            hasSearched = true
            errorMessage = error.localizedDescription
        }

        finishRequest(revision: revision, query: requestedQuery)
    }

    /// Commit a quick-search snapshot only when the user chooses a destination.
    func adopt(query: String, hubs: [PlexHub], destination: PlexNavigationRoute? = nil) {
        reset()
        text = query
        displayedQuery = normalizedQuery
        self.hubs = hubs
        hasSearched = !hubs.isEmpty
        pendingDestination = destination
    }

    func openPendingDestination() {
        guard let destination = pendingDestination else { return }
        navigationPath = [destination]
        pendingDestination = nil
    }

    func reset() {
        requestRevision += 1
        pendingDestination = nil
        text = ""
        navigationPath.removeAll()
        clearContent()
    }

    func hub(for route: PlexSearchHubRoute) -> PlexHub? {
        hubs.first { route.matches($0, query: displayedQuery) }
    }

    func items(in hub: PlexHub) -> [PlexMediaItem] {
        guard let path = validPath(for: hub) else {
            return hub.metadata
        }
        return itemsByHubPath[path] ?? hub.metadata
    }

    func isLoadingItems(in hub: PlexHub) -> Bool {
        guard let path = validPath(for: hub) else {
            return false
        }
        return loadingHubPaths.contains(path)
    }

    func itemsErrorMessage(in hub: PlexHub) -> String? {
        guard let path = validPath(for: hub) else {
            return nil
        }
        return errorMessagesByHubPath[path]
    }

    func hasMoreItems(in hub: PlexHub) -> Bool {
        guard let path = validPath(for: hub) else {
            return false
        }
        if !loadedHubPaths.contains(path) {
            let advertisedTotal = hub.totalSize ?? hub.size ?? hub.metadata.count
            return hub.more || advertisedTotal > hub.metadata.count
        }
        let items = itemsByHubPath[path] ?? []
        let totalSize = totalSizesByHubPath[path] ?? items.count
        return items.count < totalSize
    }

    func loadItems(
        in hub: PlexHub,
        forceRefresh: Bool = false,
        loadPage: (String, Int, Int) async throws -> PlexMediaPage
    ) async {
        guard let path = validPath(for: hub),
              !loadingHubPaths.contains(path) else {
            return
        }
        if loadedHubPaths.contains(path), !forceRefresh {
            return
        }

        loadingHubPaths.insert(path)
        let revision = expandedContentRevision
        defer {
            if expandedContentRevision == revision {
                loadingHubPaths.remove(path)
            }
        }

        do {
            let page = try await loadPage(path, 0, pageSize)
            guard expandedContentRevision == revision else {
                return
            }
            itemsByHubPath[path] = page.items
            totalSizesByHubPath[path] = page.totalSize ?? hub.totalSize ?? page.items.count
            loadedHubPaths.insert(path)
            errorMessagesByHubPath[path] = nil
        } catch {
            guard expandedContentRevision == revision,
                  !Task.isCancelled else {
                return
            }
            errorMessagesByHubPath[path] = error.localizedDescription
        }
    }

    func loadMoreItemsIfNeeded(
        in hub: PlexHub,
        currentItem: PlexMediaItem,
        loadPage: (String, Int, Int) async throws -> PlexMediaPage
    ) async {
        guard let path = validPath(for: hub),
              itemsByHubPath[path]?.last?.id == currentItem.id,
              hasMoreItems(in: hub),
              !loadingHubPaths.contains(path) else {
            return
        }

        loadingHubPaths.insert(path)
        let revision = expandedContentRevision
        defer {
            if expandedContentRevision == revision {
                loadingHubPaths.remove(path)
            }
        }

        do {
            let existingItems = itemsByHubPath[path] ?? []
            let page = try await loadPage(path, existingItems.count, pageSize)
            guard expandedContentRevision == revision else {
                return
            }
            let existingIDs = Set(existingItems.map(\.id))
            itemsByHubPath[path] = existingItems
                + page.items.filter { !existingIDs.contains($0.id) }
            totalSizesByHubPath[path] = page.totalSize
                ?? totalSizesByHubPath[path]
                ?? hub.totalSize
                ?? page.items.count
            errorMessagesByHubPath[path] = nil
        } catch {
            guard expandedContentRevision == revision,
                  !Task.isCancelled else {
                return
            }
            errorMessagesByHubPath[path] = error.localizedDescription
        }
    }

    func replaceCachedWatchedState(with refreshedItem: PlexMediaItem) {
        hubs = hubs.map { hub in
            var updatedHub = hub
            updatedHub.metadata = hub.metadata.map { item in
                guard item.ratingKey == refreshedItem.ratingKey else {
                    return item
                }
                return item.mergingWatchedState(from: refreshedItem)
            }
            return updatedHub
        }
        itemsByHubPath = itemsByHubPath.mapValues { items in
            items.map { item in
                guard item.ratingKey == refreshedItem.ratingKey else {
                    return item
                }
                return item.mergingWatchedState(from: refreshedItem)
            }
        }
    }

    func replaceCachedUserRating(with refreshedItem: PlexMediaItem) {
        hubs = hubs.map { hub in
            var updatedHub = hub
            updatedHub.metadata = hub.metadata.map { item in
                guard item.ratingKey == refreshedItem.ratingKey else {
                    return item
                }
                return item.mergingUserRating(from: refreshedItem)
            }
            return updatedHub
        }
        itemsByHubPath = itemsByHubPath.mapValues { items in
            items.map { item in
                guard item.ratingKey == refreshedItem.ratingKey else {
                    return item
                }
                return item.mergingUserRating(from: refreshedItem)
            }
        }
    }

    private func clearContent() {
        navigationPath.removeAll()
        displayedQuery = ""
        pendingQuery = nil
        hubs = []
        hasSearched = false
        errorMessage = nil
        clearExpandedHubContent()
    }

    private func clearExpandedHubContent() {
        expandedContentRevision += 1
        itemsByHubPath = [:]
        totalSizesByHubPath = [:]
        loadedHubPaths = []
        loadingHubPaths = []
        errorMessagesByHubPath = [:]
    }

    private func validPath(for hub: PlexHub) -> String? {
        guard let path = hub.key,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return path
    }

    private func finishRequest(revision: Int, query: String) {
        guard requestRevision == revision, pendingQuery == query else {
            return
        }
        pendingQuery = nil
    }
}
