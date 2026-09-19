import PlexClientKit
import PlexModels
import Foundation

struct PlexRelatedContentState {
    var hubsByRatingKey: [String: [PlexHub]] = [:]
    var loadedRatingKeys: Set<String> = []
    var loadingRatingKeys: Set<String> = []
    var errorMessagesByRatingKey: [String: String] = [:]
    var recency: [String] = []
    var itemsByHubRoute: [PlexRelatedHubRoute: [PlexMediaItem]] = [:]
    var totalSizesByHubRoute: [PlexRelatedHubRoute: Int] = [:]
    var loadedHubRoutes: Set<PlexRelatedHubRoute> = []
    var loadingHubRoutes: Set<PlexRelatedHubRoute> = []
    var errorMessagesByHubRoute: [PlexRelatedHubRoute: String] = [:]
}

extension PlexBrowserStore {
    func relatedHubs(for item: PlexMediaItem) -> [PlexHub] {
        relatedContentState.hubsByRatingKey[item.ratingKey] ?? []
    }

    func hasLoadedRelatedContent(for item: PlexMediaItem) -> Bool {
        relatedContentState.loadedRatingKeys.contains(item.ratingKey)
    }

    func isLoadingRelatedContent(for item: PlexMediaItem) -> Bool {
        relatedContentState.loadingRatingKeys.contains(item.ratingKey)
    }

    func relatedContentErrorMessage(for item: PlexMediaItem) -> String? {
        relatedContentState.errorMessagesByRatingKey[item.ratingKey]
    }

    func relatedHub(for route: PlexRelatedHubRoute) -> PlexHub? {
        relatedContentState.hubsByRatingKey[route.sourceRatingKey]?
            .first { route.matches(sourceRatingKey: route.sourceRatingKey, hub: $0) }
    }

    func relatedHubItems(for route: PlexRelatedHubRoute) -> [PlexMediaItem] {
        guard let hub = relatedHub(for: route) else {
            return []
        }
        return relatedContentState.itemsByHubRoute[route] ?? hub.metadata
    }

    func isLoadingRelatedHubItems(for route: PlexRelatedHubRoute) -> Bool {
        relatedContentState.loadingHubRoutes.contains(route)
    }

    func relatedHubItemsErrorMessage(for route: PlexRelatedHubRoute) -> String? {
        relatedContentState.errorMessagesByHubRoute[route]
    }

    func hasMoreRelatedHubItems(for route: PlexRelatedHubRoute) -> Bool {
        guard let hub = relatedHub(for: route) else {
            return false
        }
        if !relatedContentState.loadedHubRoutes.contains(route) {
            let advertisedTotal = hub.totalSize ?? hub.size ?? hub.metadata.count
            return hub.more || advertisedTotal > hub.metadata.count
        }
        let items = relatedContentState.itemsByHubRoute[route] ?? []
        let totalSize = relatedContentState.totalSizesByHubRoute[route] ?? items.count
        return items.count < totalSize
    }

    func replaceCachedRelatedWatchedState(with refreshedItem: PlexMediaItem) {
        relatedContentState.hubsByRatingKey = relatedContentState.hubsByRatingKey.mapValues { hubs in
            hubs.map { hub in
                var updatedHub = hub
                updatedHub.metadata = hub.metadata.map { item in
                    item.mergingWatchedState(from: refreshedItem)
                }
                return updatedHub
            }
        }
        relatedContentState.itemsByHubRoute = relatedContentState.itemsByHubRoute.mapValues {
            $0.map { item in
                item.mergingWatchedState(from: refreshedItem)
            }
        }
    }

    func replaceCachedRelatedUserRating(with refreshedItem: PlexMediaItem) {
        relatedContentState.hubsByRatingKey = relatedContentState.hubsByRatingKey.mapValues { hubs in
            hubs.map { hub in
                var updatedHub = hub
                updatedHub.metadata = hub.metadata.map { item in
                    item.mergingUserRating(from: refreshedItem)
                }
                return updatedHub
            }
        }
        relatedContentState.itemsByHubRoute = relatedContentState.itemsByHubRoute.mapValues {
            $0.map { item in
                item.mergingUserRating(from: refreshedItem)
            }
        }
    }

    func resetRelatedContent() {
        relatedContentGenerationsByRatingKey.removeAll()
        relatedContentState = PlexRelatedContentState()
    }

    func loadRelatedContent(
        for item: PlexMediaItem,
        forceRefresh: Bool = false
    ) async {
        guard connectionStore.settings.hasValidConfiguration else {
            resetRelatedContent()
            return
        }
        guard !relatedContentState.loadingRatingKeys.contains(item.ratingKey) else {
            return
        }
        if relatedContentState.loadedRatingKeys.contains(item.ratingKey), !forceRefresh {
            recordRelatedContentAccess(item.ratingKey)
            return
        }

        let generation = relatedContentGeneration(for: item.ratingKey)
        relatedContentState.loadingRatingKeys.insert(item.ratingKey)
        defer {
            if relatedContentGenerationsByRatingKey[item.ratingKey] == generation {
                relatedContentState.loadingRatingKeys.remove(item.ratingKey)
            }
        }

        do {
            let hubs = try await connectionStore.perform { configuration in
                try await client.fetchRelatedHubs(
                    ratingKey: item.ratingKey,
                    using: configuration
                )
            }
            guard relatedContentGenerationsByRatingKey[item.ratingKey] == generation else {
                return
            }

            relatedContentState.loadingRatingKeys.remove(item.ratingKey)
            relatedContentGenerationsByRatingKey[item.ratingKey] = UUID()
            relatedContentState.loadingHubRoutes.subtract(
                relatedContentState.loadingHubRoutes.filter {
                    $0.sourceRatingKey == item.ratingKey
                }
            )
            removeStaleRelatedHubPages(for: item.ratingKey, keeping: hubs)
            relatedContentState.hubsByRatingKey[item.ratingKey] = hubs
            relatedContentState.loadedRatingKeys.insert(item.ratingKey)
            relatedContentState.errorMessagesByRatingKey[item.ratingKey] = nil
            recordRelatedContentAccess(item.ratingKey)
        } catch {
            guard relatedContentGenerationsByRatingKey[item.ratingKey] == generation,
                  !Task.isCancelled else {
                return
            }
            relatedContentState.errorMessagesByRatingKey[item.ratingKey] = error.localizedDescription
            recordRelatedContentAccess(item.ratingKey)
        }
    }

    func loadRelatedHubItems(
        for route: PlexRelatedHubRoute,
        forceRefresh: Bool = false
    ) async {
        await loadRelatedHubItems(
            for: route,
            forceRefresh: forceRefresh,
            loadPage: fetchRelatedHubPage
        )
    }

    func loadRelatedHubItems(
        for route: PlexRelatedHubRoute,
        forceRefresh: Bool = false,
        loadPage: (String, Int) async throws -> PlexMediaPage
    ) async {
        guard let hub = relatedHub(for: route),
              !relatedContentState.loadingHubRoutes.contains(route),
              let generation = relatedContentGenerationsByRatingKey[route.sourceRatingKey] else {
            return
        }
        if relatedContentState.loadedHubRoutes.contains(route), !forceRefresh {
            recordRelatedContentAccess(route.sourceRatingKey)
            return
        }

        relatedContentState.loadingHubRoutes.insert(route)
        defer {
            if relatedContentGenerationsByRatingKey[route.sourceRatingKey] == generation {
                relatedContentState.loadingHubRoutes.remove(route)
            }
        }

        do {
            let page = try await loadPage(route.hubKey, 0)
            guard relatedContentGenerationsByRatingKey[route.sourceRatingKey] == generation,
                  relatedHub(for: route) != nil else {
                return
            }
            relatedContentState.itemsByHubRoute[route] = page.items
            relatedContentState.totalSizesByHubRoute[route] = page.totalSize
                ?? hub.totalSize
                ?? page.items.count
            relatedContentState.loadedHubRoutes.insert(route)
            relatedContentState.errorMessagesByHubRoute[route] = nil
            recordRelatedContentAccess(route.sourceRatingKey)
        } catch {
            guard relatedContentGenerationsByRatingKey[route.sourceRatingKey] == generation,
                  !Task.isCancelled else {
                return
            }
            relatedContentState.errorMessagesByHubRoute[route] = error.localizedDescription
            recordRelatedContentAccess(route.sourceRatingKey)
        }
    }

    func loadMoreRelatedHubItemsIfNeeded(
        for route: PlexRelatedHubRoute,
        currentItem: PlexMediaItem
    ) async {
        guard let hub = relatedHub(for: route),
              relatedContentState.itemsByHubRoute[route]?.last?.id == currentItem.id,
              hasMoreRelatedHubItems(for: route),
              !relatedContentState.loadingHubRoutes.contains(route),
              let generation = relatedContentGenerationsByRatingKey[route.sourceRatingKey] else {
            return
        }

        relatedContentState.loadingHubRoutes.insert(route)
        defer {
            if relatedContentGenerationsByRatingKey[route.sourceRatingKey] == generation {
                relatedContentState.loadingHubRoutes.remove(route)
            }
        }

        do {
            let existingItems = relatedContentState.itemsByHubRoute[route] ?? []
            let page = try await fetchRelatedHubPage(
                path: route.hubKey,
                start: existingItems.count
            )
            guard relatedContentGenerationsByRatingKey[route.sourceRatingKey] == generation,
                  relatedHub(for: route) != nil else {
                return
            }
            let existingIDs = Set(existingItems.map(\.id))
            relatedContentState.itemsByHubRoute[route] = existingItems
                + page.items.filter { !existingIDs.contains($0.id) }
            relatedContentState.totalSizesByHubRoute[route] = page.totalSize
                ?? relatedContentState.totalSizesByHubRoute[route]
                ?? hub.totalSize
                ?? page.items.count
            relatedContentState.errorMessagesByHubRoute[route] = nil
            recordRelatedContentAccess(route.sourceRatingKey)
        } catch {
            guard relatedContentGenerationsByRatingKey[route.sourceRatingKey] == generation,
                  !Task.isCancelled else {
                return
            }
            relatedContentState.errorMessagesByHubRoute[route] = error.localizedDescription
            recordRelatedContentAccess(route.sourceRatingKey)
        }
    }
}

private extension PlexBrowserStore {
    func relatedContentGeneration(for ratingKey: String) -> UUID {
        if let generation = relatedContentGenerationsByRatingKey[ratingKey] {
            return generation
        }
        let generation = UUID()
        relatedContentGenerationsByRatingKey[ratingKey] = generation
        return generation
    }

    func fetchRelatedHubPage(path: String, start: Int) async throws -> PlexMediaPage {
        try await connectionStore.perform { configuration in
            try await client.fetchMediaPage(
                contentPath: path,
                using: configuration,
                start: start,
                size: pageSize
            )
        }
    }

    func removeStaleRelatedHubPages(for ratingKey: String, keeping hubs: [PlexHub]) {
        let retainedRoutes = Set(hubs.compactMap { hub in
            PlexRelatedHubRoute(
                sourceRatingKey: ratingKey,
                hub: hub
            )
        })
        let staleRoutes = relatedHubRoutes(for: ratingKey).filter {
            $0.sourceRatingKey == ratingKey && !retainedRoutes.contains($0)
        }
        for route in staleRoutes {
            removeRelatedHubPage(for: route)
        }
    }

    func removeRelatedHubPage(for route: PlexRelatedHubRoute) {
        relatedContentState.itemsByHubRoute[route] = nil
        relatedContentState.totalSizesByHubRoute[route] = nil
        relatedContentState.loadedHubRoutes.remove(route)
        relatedContentState.loadingHubRoutes.remove(route)
        relatedContentState.errorMessagesByHubRoute[route] = nil
    }

    func relatedHubRoutes(for ratingKey: String) -> Set<PlexRelatedHubRoute> {
        Set(relatedContentState.itemsByHubRoute.keys)
            .union(relatedContentState.totalSizesByHubRoute.keys)
            .union(relatedContentState.loadedHubRoutes)
            .union(relatedContentState.loadingHubRoutes)
            .union(relatedContentState.errorMessagesByHubRoute.keys)
            .filter { $0.sourceRatingKey == ratingKey }
    }

    func recordRelatedContentAccess(_ ratingKey: String) {
        relatedContentState.recency.removeAll { $0 == ratingKey }
        relatedContentState.recency.append(ratingKey)

        while relatedContentState.recency.count > relatedContentLimit {
            let evictedRatingKey = relatedContentState.recency.removeFirst()
            relatedContentState.hubsByRatingKey[evictedRatingKey] = nil
            relatedContentState.loadedRatingKeys.remove(evictedRatingKey)
            relatedContentState.loadingRatingKeys.remove(evictedRatingKey)
            relatedContentState.errorMessagesByRatingKey[evictedRatingKey] = nil
            relatedContentGenerationsByRatingKey[evictedRatingKey] = nil

            let evictedRoutes = relatedHubRoutes(for: evictedRatingKey)
            for route in evictedRoutes {
                removeRelatedHubPage(for: route)
            }
        }
    }
}
