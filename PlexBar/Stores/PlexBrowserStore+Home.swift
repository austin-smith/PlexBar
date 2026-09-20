import PlexClientKit
import PlexModels
import Foundation

struct PlexHomeState {
    var hubs: [PlexHub] = []
    var hasLoadedHubs = false
    var isLoadingHubs = false
    var hubsErrorMessage: String?
    var itemsByHubPath: [String: [PlexMediaItem]] = [:]
    var totalSizesByHubPath: [String: Int] = [:]
    var loadedHubPaths: Set<String> = []
    var loadingHubPaths: Set<String> = []
    var errorMessagesByHubPath: [String: String] = [:]
}

extension PlexBrowserStore {
    var homeHubs: [PlexHub] {
        homeState.hubs.filter { !$0.metadata.isEmpty }
    }

    var hasLoadedHomeHubs: Bool {
        homeState.hasLoadedHubs
    }

    var isLoadingHomeHubs: Bool {
        homeState.isLoadingHubs
    }

    var homeHubsErrorMessage: String? {
        homeState.hubsErrorMessage
    }

    func loadHomeHubs(forceRefresh: Bool = false) async {
        guard !Task.isCancelled else { return }
        let stateID = serverStateID
        guard connectionStore.settings.hasValidConfiguration else {
            homeState = PlexHomeState()
            return
        }
        guard !homeState.isLoadingHubs else {
            return
        }
        if homeState.hasLoadedHubs, !forceRefresh {
            return
        }

        homeState.isLoadingHubs = true
        defer {
            if serverStateID == stateID {
                homeState.isLoadingHubs = false
            }
        }

        do {
            let hubs = try await connectionStore.perform { configuration in
                let endpoints = try await self.advertisedLibraryProviderEndpoints(
                    using: configuration
                )
                return try await client.fetchHomeHubs(
                    endpoints: endpoints,
                    using: configuration
                )
            }
            try Task.checkCancellation()
            guard serverStateID == stateID else { return }
            homeState.hubs = hubs
            homeState.hasLoadedHubs = true
            homeState.hubsErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard serverStateID == stateID, !Task.isCancelled else {
                return
            }
            homeState.hubsErrorMessage = error.localizedDescription
        }
    }

    func homeHubItems(in hub: PlexHub) -> [PlexMediaItem] {
        guard let path = hub.key else {
            return hub.metadata
        }
        return homeState.itemsByHubPath[path] ?? hub.metadata
    }

    func isLoadingHomeHubItems(in hub: PlexHub) -> Bool {
        guard let path = hub.key else {
            return false
        }
        return homeState.loadingHubPaths.contains(path)
    }

    func homeHubItemsErrorMessage(in hub: PlexHub) -> String? {
        guard let path = hub.key else {
            return nil
        }
        return homeState.errorMessagesByHubPath[path]
    }

    func hasMoreHomeHubItems(in hub: PlexHub) -> Bool {
        guard let path = hub.key else {
            return false
        }
        if !homeState.loadedHubPaths.contains(path) {
            return hub.more
        }
        let items = homeState.itemsByHubPath[path] ?? []
        let totalSize = homeState.totalSizesByHubPath[path] ?? items.count
        return items.count < totalSize
    }

    func loadHomeHubItems(in hub: PlexHub, forceRefresh: Bool = false) async {
        guard let path = hub.key,
              !homeState.loadingHubPaths.contains(path) else {
            return
        }
        if homeState.loadedHubPaths.contains(path), !forceRefresh {
            return
        }

        homeState.loadingHubPaths.insert(path)
        defer { homeState.loadingHubPaths.remove(path) }

        do {
            let page = try await fetchHomeHubPage(path: path, start: 0)
            homeState.itemsByHubPath[path] = page.items
            homeState.totalSizesByHubPath[path] = page.totalSize ?? hub.totalSize ?? page.items.count
            homeState.loadedHubPaths.insert(path)
            homeState.errorMessagesByHubPath[path] = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            homeState.errorMessagesByHubPath[path] = error.localizedDescription
        }
    }

    func loadMoreHomeHubItemsIfNeeded(
        in hub: PlexHub,
        currentItem: PlexMediaItem
    ) async {
        guard let path = hub.key,
              homeState.itemsByHubPath[path]?.last?.id == currentItem.id,
              hasMoreHomeHubItems(in: hub),
              !homeState.loadingHubPaths.contains(path) else {
            return
        }

        homeState.loadingHubPaths.insert(path)
        defer { homeState.loadingHubPaths.remove(path) }

        do {
            let existingItems = homeState.itemsByHubPath[path] ?? []
            let page = try await fetchHomeHubPage(path: path, start: existingItems.count)
            let existingIDs = Set(existingItems.map(\.id))
            homeState.itemsByHubPath[path] = existingItems
                + page.items.filter { !existingIDs.contains($0.id) }
            homeState.totalSizesByHubPath[path] = page.totalSize
                ?? homeState.totalSizesByHubPath[path]
                ?? hub.totalSize
                ?? page.items.count
            homeState.errorMessagesByHubPath[path] = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            homeState.errorMessagesByHubPath[path] = error.localizedDescription
        }
    }
}

private extension PlexBrowserStore {
    func fetchHomeHubPage(path: String, start: Int) async throws -> PlexMediaPage {
        try await connectionStore.perform { configuration in
            try await client.fetchMediaPage(
                contentPath: path,
                using: configuration,
                start: start,
                size: pageSize
            )
        }
    }
}
