import PlexModels
import Foundation

struct PlexMediaExtrasState {
    var itemsByRatingKey: [String: [PlexMediaItem]] = [:]
    var loadedRatingKeys: Set<String> = []
    var loadingRatingKeys: Set<String> = []
    var errorMessagesByRatingKey: [String: String] = [:]
    var recency: [String] = []
}

extension PlexBrowserStore {
    func mediaExtras(for item: PlexMediaItem) -> [PlexMediaItem] {
        mediaExtrasState.itemsByRatingKey[item.ratingKey] ?? []
    }

    func hasLoadedMediaExtras(for item: PlexMediaItem) -> Bool {
        mediaExtrasState.loadedRatingKeys.contains(item.ratingKey)
    }

    func isLoadingMediaExtras(for item: PlexMediaItem) -> Bool {
        mediaExtrasState.loadingRatingKeys.contains(item.ratingKey)
    }

    func mediaExtrasErrorMessage(for item: PlexMediaItem) -> String? {
        mediaExtrasState.errorMessagesByRatingKey[item.ratingKey]
    }

    func replaceCachedMediaExtrasWatchedState(with refreshedItem: PlexMediaItem) {
        mediaExtrasState.itemsByRatingKey = mediaExtrasState.itemsByRatingKey.mapValues { items in
            items.map { item in
                item.mergingWatchedState(from: refreshedItem)
            }
        }
    }

    func replaceCachedMediaExtrasUserRating(with refreshedItem: PlexMediaItem) {
        mediaExtrasState.itemsByRatingKey = mediaExtrasState.itemsByRatingKey.mapValues { items in
            items.map { item in
                item.mergingUserRating(from: refreshedItem)
            }
        }
    }

    func resetMediaExtras() {
        mediaExtrasGenerationsByRatingKey.removeAll()
        mediaExtrasState = PlexMediaExtrasState()
    }

    func loadMediaExtras(
        for item: PlexMediaItem,
        forceRefresh: Bool = false
    ) async {
        await loadMediaExtras(
            for: item,
            forceRefresh: forceRefresh,
            load: fetchMediaExtras
        )
    }

    func loadMediaExtras(
        for item: PlexMediaItem,
        forceRefresh: Bool = false,
        load: (String) async throws -> [PlexMediaItem]
    ) async {
        guard item.supportsMediaExtras else { return }
        guard connectionStore.settings.hasValidConfiguration else {
            resetMediaExtras()
            return
        }
        guard !mediaExtrasState.loadingRatingKeys.contains(item.ratingKey) else {
            return
        }
        if mediaExtrasState.loadedRatingKeys.contains(item.ratingKey), !forceRefresh {
            recordMediaExtrasAccess(item.ratingKey)
            return
        }

        let generation = mediaExtrasGeneration(for: item.ratingKey)
        mediaExtrasState.loadingRatingKeys.insert(item.ratingKey)
        defer {
            if mediaExtrasGenerationsByRatingKey[item.ratingKey] == generation {
                mediaExtrasState.loadingRatingKeys.remove(item.ratingKey)
            }
        }

        do {
            let extras = try await load(item.ratingKey)
            guard mediaExtrasGenerationsByRatingKey[item.ratingKey] == generation else {
                return
            }
            mediaExtrasState.itemsByRatingKey[item.ratingKey] = extras
            mediaExtrasState.loadedRatingKeys.insert(item.ratingKey)
            mediaExtrasState.errorMessagesByRatingKey[item.ratingKey] = nil
            recordMediaExtrasAccess(item.ratingKey)
        } catch {
            guard mediaExtrasGenerationsByRatingKey[item.ratingKey] == generation,
                  !Task.isCancelled else {
                return
            }
            mediaExtrasState.errorMessagesByRatingKey[item.ratingKey] = error.localizedDescription
            recordMediaExtrasAccess(item.ratingKey)
        }
    }
}

private extension PlexBrowserStore {
    func mediaExtrasGeneration(for ratingKey: String) -> UUID {
        if let generation = mediaExtrasGenerationsByRatingKey[ratingKey] {
            return generation
        }
        let generation = UUID()
        mediaExtrasGenerationsByRatingKey[ratingKey] = generation
        return generation
    }

    func fetchMediaExtras(ratingKey: String) async throws -> [PlexMediaItem] {
        try await connectionStore.perform { configuration in
            try await client.fetchMediaExtras(
                ratingKey: ratingKey,
                using: configuration
            )
        }
    }

    func recordMediaExtrasAccess(_ ratingKey: String) {
        mediaExtrasState.recency.removeAll { $0 == ratingKey }
        mediaExtrasState.recency.append(ratingKey)

        while mediaExtrasState.recency.count > mediaExtrasLimit {
            let evictedRatingKey = mediaExtrasState.recency.removeFirst()
            mediaExtrasState.itemsByRatingKey[evictedRatingKey] = nil
            mediaExtrasState.loadedRatingKeys.remove(evictedRatingKey)
            mediaExtrasState.loadingRatingKeys.remove(evictedRatingKey)
            mediaExtrasState.errorMessagesByRatingKey[evictedRatingKey] = nil
            mediaExtrasGenerationsByRatingKey[evictedRatingKey] = nil
        }
    }
}
