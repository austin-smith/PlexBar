import PlexClientKit
import PlexModels
import Foundation
import Observation

@MainActor
@Observable
final class PlexBrowserStore {
    let connectionStore: PlexConnectionStore
    let client: PlexAPIClient
    private let playbackCapabilities: PlexPlaybackCapabilities
    let pageSize: Int
    let transientLibraryRequestLimit: Int
    let relatedContentLimit: Int
    let mediaExtrasLimit: Int
    let peopleLimit: Int
    let globalSearchStore: PlexGlobalSearchStore

    private(set) var serverStateID = UUID()
    var homeState = PlexHomeState()
    var relatedContentState = PlexRelatedContentState()
    var relatedContentGenerationsByRatingKey: [String: UUID] = [:]
    var mediaExtrasState = PlexMediaExtrasState()
    var mediaExtrasGenerationsByRatingKey: [String: UUID] = [:]
    var peopleState = PlexPeopleState()
    var peopleGenerationsByIdentifier: [String: UUID] = [:]
    private var libraryItems: [PlexLibraryRequest: [PlexMediaItem]] = [:]
    private var libraryTotalSizes: [PlexLibraryRequest: Int] = [:]
    private var loadingLibraries: Set<PlexLibraryRequest> = []
    private var libraryErrorMessages: [PlexLibraryRequest: String] = [:]
    private var transientLibraryRequestRecency: [String: [PlexLibraryRequest]] = [:]
    private var libraryBrowseDefinitions: [String: PlexLibraryBrowseDefinition] = [:]
    private var libraryBrowseDefinitionTasks: [String: Task<PlexLibraryBrowseDefinition, Error>] = [:]
    var collectionItemsByLibraryID: [String: [PlexMediaItem]] = [:]
    var collectionTotalSizesByLibraryID: [String: Int] = [:]
    var loadingCollectionLibraryIDs: Set<String> = []
    var collectionErrorMessagesByLibraryID: [String: String] = [:]
    var playlists: [PlexMediaItem] = []
    var playlistsTotalSize: Int?
    var isLoadingPlaylists = false
    var playlistsErrorMessage: String?
    private var childItems: [String: [PlexMediaItem]] = [:]
    private var childTotalSizes: [String: Int] = [:]
    private var loadingChildPaths: Set<String> = []
    private var childErrorMessages: [String: String] = [:]
    private var resolvedMediaItemsByRoute: [PlexMediaRoute: PlexMediaItem] = [:]
    var libraryFilterValuesByCacheKey: [String: [PlexLibraryFilterValue]] = [:]
    var loadingLibraryFilterValueKeys: Set<String> = []
    var libraryFilterValueErrorMessages: [String: String] = [:]
    private var providerEndpointsByConnectionKey: [String: PlexLibraryProviderEndpoints] = [:]
    private var providerEndpointTasksByConnectionKey: [String: Task<PlexLibraryProviderEndpoints, Error>] = [:]
    private(set) var presentedProviderEndpoints: PlexLibraryProviderEndpoints?
    private var presentedProviderConnectionKey: String?
    private(set) var watchedStateMutationRatingKeys: Set<String> = []
    private(set) var personalRatingMutationRatingKeys: Set<String> = []
    private(set) var metadataRefreshRatingKeys: Set<String> = []
    private(set) var continueWatchingRemovalRatingKeys: Set<String> = []
    private(set) var collectionPlaylistMutationKeys: Set<String> = []

    init(
        connectionStore: PlexConnectionStore,
        client: PlexAPIClient = PlexAPIClient(),
        playbackCapabilities: PlexPlaybackCapabilities = NativePlaybackCapabilityProbe.current(),
        pageSize: Int = 100,
        transientLibraryRequestLimit: Int = 8,
        relatedContentLimit: Int = 12,
        mediaExtrasLimit: Int = 12,
        peopleLimit: Int = 48,
        globalSearchDebounceDuration: Duration = .milliseconds(300)
    ) {
        self.connectionStore = connectionStore
        self.client = client
        self.playbackCapabilities = playbackCapabilities
        self.pageSize = max(pageSize, 1)
        self.transientLibraryRequestLimit = max(transientLibraryRequestLimit, 1)
        self.relatedContentLimit = max(relatedContentLimit, 1)
        self.mediaExtrasLimit = max(mediaExtrasLimit, 1)
        self.peopleLimit = max(peopleLimit, 1)
        globalSearchStore = PlexGlobalSearchStore(
            debounceDuration: globalSearchDebounceDuration,
            pageSize: self.pageSize
        )
    }
}

extension PlexBrowserStore {
    func resetServerScopedState() {
        serverStateID = UUID()
        libraryBrowseDefinitionTasks.values.forEach { $0.cancel() }
        providerEndpointTasksByConnectionKey.values.forEach { $0.cancel() }

        homeState = PlexHomeState()
        resetDetailDiscoveryContent()
        globalSearchStore.reset()

        libraryItems.removeAll()
        libraryTotalSizes.removeAll()
        loadingLibraries.removeAll()
        libraryErrorMessages.removeAll()
        transientLibraryRequestRecency.removeAll()
        libraryBrowseDefinitions.removeAll()
        libraryBrowseDefinitionTasks.removeAll()

        collectionItemsByLibraryID.removeAll()
        collectionTotalSizesByLibraryID.removeAll()
        loadingCollectionLibraryIDs.removeAll()
        collectionErrorMessagesByLibraryID.removeAll()

        playlists.removeAll()
        playlistsTotalSize = nil
        isLoadingPlaylists = false
        playlistsErrorMessage = nil

        childItems.removeAll()
        childTotalSizes.removeAll()
        loadingChildPaths.removeAll()
        childErrorMessages.removeAll()
        resolvedMediaItemsByRoute.removeAll()

        libraryFilterValuesByCacheKey.removeAll()
        loadingLibraryFilterValueKeys.removeAll()
        libraryFilterValueErrorMessages.removeAll()

        providerEndpointsByConnectionKey.removeAll()
        providerEndpointTasksByConnectionKey.removeAll()
        presentedProviderEndpoints = nil
        presentedProviderConnectionKey = nil

        watchedStateMutationRatingKeys.removeAll()
        personalRatingMutationRatingKeys.removeAll()
        metadataRefreshRatingKeys.removeAll()
        continueWatchingRemovalRatingKeys.removeAll()
        collectionPlaylistMutationKeys.removeAll()
    }

    func homeHub(for route: PlexHomeHubRoute) -> PlexHub? {
        homeState.hubs.first(where: route.matches)
    }

    func item(for route: PlexMediaRoute) -> PlexMediaItem? {
        if let resolvedItem = resolvedMediaItemsByRoute[route] {
            return resolvedItem
        }

        let libraryItem = libraryItems.values
            .lazy
            .flatMap { $0 }
            .first(where: route.matches)
        if let libraryItem {
            return libraryItem
        }

        let homeItem = homeState.hubs
            .lazy
            .flatMap(\.metadata)
            .first(where: route.matches)
            ?? homeState.itemsByHubPath.values
                .lazy
                .flatMap { $0 }
                .first(where: route.matches)
        if let homeItem {
            return homeItem
        }

        let searchItem = globalSearchStore.hubs
            .lazy
            .flatMap(\.metadata)
            .first(where: route.matches)
            ?? globalSearchStore.itemsByHubPath.values
                .lazy
                .flatMap { $0 }
                .first(where: route.matches)
        if let searchItem {
            return searchItem
        }

        let relatedItem = relatedContentState.hubsByRatingKey.values
            .lazy
            .flatMap { $0 }
            .flatMap(\.metadata)
            .first(where: route.matches)
            ?? relatedContentState.itemsByHubRoute.values
                .lazy
                .flatMap { $0 }
                .first(where: route.matches)
        if let relatedItem {
            return relatedItem
        }

        let extraItem = mediaExtrasState.itemsByRatingKey.values
            .lazy
            .flatMap { $0 }
            .first(where: route.matches)
        if let extraItem {
            return extraItem
        }

        let collectionItem = collectionItemsByLibraryID.values
            .lazy
            .flatMap { $0 }
            .first(where: route.matches)
        if let collectionItem {
            return collectionItem
        }

        if let playlistItem = playlists.first(where: route.matches) {
            return playlistItem
        }

        return childItems.values
            .lazy
            .flatMap { $0 }
            .first(where: route.matches)
    }

    func resolveItem(for route: PlexMediaRoute) async throws -> PlexMediaItem {
        if let item = item(for: route) {
            return item
        }

        let item = try await connectionStore.perform { configuration in
            try await client.fetchMediaMetadata(
                ratingKey: route.ratingKey,
                using: configuration
            )
        }
        resolvedMediaItemsByRoute[route] = item
        return item
    }

    func resetResolvedMediaItems() {
        resolvedMediaItemsByRoute.removeAll()
    }

    func browseDefinition(for library: PlexLibrary) -> PlexLibraryBrowseDefinition? {
        libraryBrowseDefinitions[library.id]
    }

    func items(
        in library: PlexLibrary,
        searchQuery: String = "",
        browseOptions: PlexLibraryBrowseOptions = .default
    ) -> [PlexMediaItem] {
        let request = PlexLibraryRequest(
            libraryID: library.id,
            searchQuery: searchQuery,
            browseOptions: browseOptions
        )
        return libraryItems[request] ?? []
    }

    func isLoading(
        _ library: PlexLibrary,
        searchQuery: String = "",
        browseOptions: PlexLibraryBrowseOptions = .default
    ) -> Bool {
        loadingLibraries.contains(PlexLibraryRequest(
            libraryID: library.id,
            searchQuery: searchQuery,
            browseOptions: browseOptions
        ))
    }

    func errorMessage(
        for library: PlexLibrary,
        searchQuery: String = "",
        browseOptions: PlexLibraryBrowseOptions = .default
    ) -> String? {
        let request = PlexLibraryRequest(
            libraryID: library.id,
            searchQuery: searchQuery,
            browseOptions: browseOptions
        )
        return libraryErrorMessages[request]
    }

    func hasMoreItems(
        in library: PlexLibrary,
        searchQuery: String = "",
        browseOptions: PlexLibraryBrowseOptions = .default
    ) -> Bool {
        let request = PlexLibraryRequest(
            libraryID: library.id,
            searchQuery: searchQuery,
            browseOptions: browseOptions
        )
        let itemCount = libraryItems[request]?.count ?? 0
        let totalSize = libraryTotalSizes[request]
            ?? (request.searchQuery.isEmpty && request.browseOptions == .default ? library.itemCount : itemCount)
        return itemCount < totalSize
    }

    func children(of item: PlexMediaItem) -> [PlexMediaItem] {
        guard let path = item.childrenPath else {
            return []
        }
        return childItems[path] ?? []
    }

    func isLoadingChildren(of item: PlexMediaItem) -> Bool {
        guard let path = item.childrenPath else {
            return false
        }
        return loadingChildPaths.contains(path)
    }

    func childrenErrorMessage(for item: PlexMediaItem) -> String? {
        guard let path = item.childrenPath else {
            return nil
        }
        return childErrorMessages[path]
    }

    func hasMoreChildren(of item: PlexMediaItem) -> Bool {
        guard let path = item.childrenPath else {
            return false
        }
        let itemCount = childItems[path]?.count ?? 0
        return itemCount < (childTotalSizes[path] ?? itemCount)
    }

    func load(
        _ library: PlexLibrary,
        searchQuery: String = "",
        browseOptions: PlexLibraryBrowseOptions = .default,
        forceRefresh: Bool = false
    ) async {
        let request = PlexLibraryRequest(
            libraryID: library.id,
            searchQuery: searchQuery,
            browseOptions: browseOptions
        )
        guard !loadingLibraries.contains(request) else {
            return
        }

        if !forceRefresh, libraryItems[request] != nil {
            recordLibraryRequestAccess(request)
            return
        }

        loadingLibraries.insert(request)
        defer { loadingLibraries.remove(request) }

        do {
            let definition = try await libraryBrowseDefinition(for: library)
            let page = try await fetchPage(request: request, definition: definition, start: 0)
            storeLibraryPage(page, for: request)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            libraryErrorMessages[request] = error.localizedDescription
            recordLibraryRequestAccess(request)
        }
    }

    func loadMoreIfNeeded(
        in library: PlexLibrary,
        searchQuery: String = "",
        browseOptions: PlexLibraryBrowseOptions = .default,
        currentItem: PlexMediaItem
    ) async {
        let request = PlexLibraryRequest(
            libraryID: library.id,
            searchQuery: searchQuery,
            browseOptions: browseOptions
        )
        guard libraryItems[request]?.last?.id == currentItem.id,
              hasMoreItems(
                  in: library,
                  searchQuery: searchQuery,
                  browseOptions: browseOptions
              ),
              !loadingLibraries.contains(request) else {
            return
        }

        loadingLibraries.insert(request)
        defer { loadingLibraries.remove(request) }

        do {
            let existingItems = libraryItems[request] ?? []
            let definition = try await libraryBrowseDefinition(for: library)
            let page = try await fetchPage(
                request: request,
                definition: definition,
                start: existingItems.count
            )
            let existingIDs = Set(existingItems.map(\.id))
            libraryItems[request] = existingItems + page.items.filter { !existingIDs.contains($0.id) }
            libraryTotalSizes[request] = page.totalSize ?? libraryTotalSizes[request]
            libraryErrorMessages[request] = nil
            recordLibraryRequestAccess(request)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            libraryErrorMessages[request] = error.localizedDescription
            recordLibraryRequestAccess(request)
        }
    }
}

extension PlexBrowserStore {
    var cacheMetrics: PlexBrowserCacheMetrics {
        let requests = Set(libraryItems.keys)
            .union(libraryTotalSizes.keys)
            .union(libraryErrorMessages.keys)
        let transientRequests = requests.filter(\.isTransient)
        return PlexBrowserCacheMetrics(
            libraryRequestCount: requests.count,
            transientLibraryRequestCount: transientRequests.count,
            libraryItemOccurrenceCount: libraryItems.values.reduce(0) { $0 + $1.count },
            uniqueLibraryItemCount: Set(
                libraryItems.values.lazy.flatMap { $0 }.map(\.id)
            ).count,
            transientRequestCountsByLibraryID: Dictionary(
                grouping: transientRequests,
                by: \.libraryID
            ).mapValues(\.count),
            transientRequestLimitPerLibrary: transientLibraryRequestLimit
        )
    }
}

private extension PlexBrowserStore {
    func storeLibraryPage(_ page: PlexMediaPage, for request: PlexLibraryRequest) {
        libraryItems[request] = page.items
        libraryTotalSizes[request] = page.totalSize ?? page.items.count
        libraryErrorMessages[request] = nil
        recordLibraryRequestAccess(request)
    }

    func recordLibraryRequestAccess(_ request: PlexLibraryRequest) {
        guard request.isTransient else {
            return
        }

        var recency = transientLibraryRequestRecency[request.libraryID] ?? []
        recency.removeAll { $0 == request }
        recency.append(request)

        while recency.count > transientLibraryRequestLimit {
            let evictedRequest = recency.removeFirst()
            libraryItems[evictedRequest] = nil
            libraryTotalSizes[evictedRequest] = nil
            libraryErrorMessages[evictedRequest] = nil
        }

        transientLibraryRequestRecency[request.libraryID] = recency
    }
}

extension PlexBrowserStore {
    func loadChildren(of item: PlexMediaItem, forceRefresh: Bool = false) async {
        guard let path = item.childrenPath,
              !loadingChildPaths.contains(path) else {
            return
        }

        if !forceRefresh, childItems[path] != nil {
            return
        }

        loadingChildPaths.insert(path)
        defer { loadingChildPaths.remove(path) }

        do {
            let page = try await fetchChildrenPage(of: item, start: 0)
            childItems[path] = page.items
            childTotalSizes[path] = page.totalSize ?? page.items.count
            childErrorMessages[path] = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            childErrorMessages[path] = error.localizedDescription
        }
    }

    func loadMoreChildrenIfNeeded(
        of parent: PlexMediaItem,
        currentItem: PlexMediaItem
    ) async {
        guard let path = parent.childrenPath,
              childItems[path]?.last?.id == currentItem.id,
              hasMoreChildren(of: parent),
              !loadingChildPaths.contains(path) else {
            return
        }

        loadingChildPaths.insert(path)
        defer { loadingChildPaths.remove(path) }

        do {
            let existingItems = childItems[path] ?? []
            let page = try await fetchChildrenPage(of: parent, start: existingItems.count)
            let existingIDs = Set(existingItems.map(\.id))
            childItems[path] = existingItems + page.items.filter { !existingIDs.contains($0.id) }
            childTotalSizes[path] = page.totalSize ?? childTotalSizes[path]
            childErrorMessages[path] = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            childErrorMessages[path] = error.localizedDescription
        }
    }

    func details(for item: PlexMediaItem) async -> PlexMediaItem {
        do {
            return try await connectionStore.perform { configuration in
                try await client.fetchMediaMetadata(
                    ratingKey: item.ratingKey,
                    using: configuration
                )
            }
        } catch {
            return item
        }
    }

    func primaryExtra(for item: PlexMediaItem) async throws -> PlexMediaItem {
        guard let path = item.primaryExtraKey?.nilIfBlank else {
            throw PlexAPIError.invalidResponse
        }

        return try await connectionStore.perform { configuration in
            try await client.fetchMediaMetadata(path: path, using: configuration)
        }
    }

    func postPlayHubs(for item: PlexMediaItem, count: Int = 12) async throws -> [PlexHub] {
        try await connectionStore.perform { configuration in
            try await client.fetchPostPlayHubs(
                ratingKey: item.ratingKey,
                using: configuration,
                count: count
            )
        }
    }

    func playbackPlan(
        for item: PlexMediaItem,
        source: PlexPlaybackSource? = nil,
        videoQuality: PlexVideoQuality = .original,
        startTimeOverride: TimeInterval? = nil,
        forceServerMediaSelection: Bool = false
    ) async throws -> PlexPlaybackPlan {
        try await connectionStore.perform { configuration in
            try await client.makePlaybackPlan(
                for: item,
                using: configuration,
                capabilities: playbackCapabilities,
                source: source,
                videoQuality: videoQuality,
                streamingPolicy: connectionStore.settings.playbackStreamingPolicy,
                startTimeOverride: startTimeOverride,
                forceServerMediaSelection: forceServerMediaSelection
            )
        }
    }

    func selectMediaStreams(
        partID: Int,
        audioStreamID: Int? = nil,
        subtitleStreamID: Int? = nil
    ) async throws {
        try await connectionStore.perform { configuration in
            try await client.selectMediaStreams(
                partID: partID,
                audioStreamID: audioStreamID,
                subtitleStreamID: subtitleStreamID,
                allParts: true,
                using: configuration
            )
        }
    }

    func refreshedPlayableDetails(for item: PlexMediaItem) async throws -> PlexMediaItem {
        try await connectionStore.perform { configuration in
            try await client.fetchMediaMetadata(ratingKey: item.ratingKey, using: configuration)
        }
    }

    func continuousPlayQueue(for item: PlexMediaItem) async throws -> PlexPlaybackQueue {
        try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            guard let playQueuePath = endpoints.playQueuePath else {
                throw PlexAPIError.missingLibraryPlayQueueFeature
            }
            return try await client.createContinuousPlayQueue(
                for: item,
                endpointPath: playQueuePath,
                using: configuration
            )
        }
    }

    func cinemaPlayQueue(
        for item: PlexMediaItem,
        extrasPrefixCount: Int
    ) async throws -> PlexPlaybackQueue {
        try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            guard let playQueuePath = endpoints.playQueuePath else {
                throw PlexAPIError.missingLibraryPlayQueueFeature
            }
            return try await client.createCinemaPlayQueue(
                for: item,
                extrasPrefixCount: extrasPrefixCount,
                endpointPath: playQueuePath,
                using: configuration
            )
        }
    }

    func refreshPlayQueueWindow(
        queueID: Int,
        centeredOn playQueueItemID: String
    ) async throws -> PlexPlayQueuePage {
        try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            guard let playQueuePath = endpoints.playQueuePath else {
                throw PlexAPIError.missingLibraryPlayQueueFeature
            }
            return try await client.fetchPlayQueuePage(
                queueID: queueID,
                endpointPath: playQueuePath,
                centeredOn: playQueueItemID,
                using: configuration
            )
        }
    }

    func addToPlayQueue(
        _ item: PlexMediaItem,
        queueID: Int,
        insertion: PlexPlayQueueInsertion
    ) async throws -> PlexPlayQueuePage {
        try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            guard let playQueuePath = endpoints.playQueuePath else {
                throw PlexAPIError.missingLibraryPlayQueueFeature
            }
            return try await client.addToPlayQueue(
                item,
                queueID: queueID,
                insertion: insertion,
                endpointPath: playQueuePath,
                using: configuration
            )
        }
    }

    func setPlayQueueShuffled(
        _ shuffled: Bool,
        queueID: Int
    ) async throws -> PlexPlayQueuePage {
        try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            guard let playQueuePath = endpoints.playQueuePath else {
                throw PlexAPIError.missingLibraryPlayQueueFeature
            }
            return try await client.setPlayQueueShuffled(
                shuffled,
                queueID: queueID,
                endpointPath: playQueuePath,
                using: configuration
            )
        }
    }

    func removePlayQueueItem(
        queueID: Int,
        playQueueItemID: String
    ) async throws -> PlexPlayQueuePage {
        try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            guard let playQueuePath = endpoints.playQueuePath else {
                throw PlexAPIError.missingLibraryPlayQueueFeature
            }
            return try await client.removePlayQueueItem(
                queueID: queueID,
                playQueueItemID: playQueueItemID,
                endpointPath: playQueuePath,
                using: configuration
            )
        }
    }

    func movePlayQueueItem(
        queueID: Int,
        move: PlexPlayQueueItemMove
    ) async throws -> PlexPlayQueuePage {
        try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            guard let playQueuePath = endpoints.playQueuePath else {
                throw PlexAPIError.missingLibraryPlayQueueFeature
            }
            return try await client.movePlayQueueItem(
                queueID: queueID,
                move: move,
                endpointPath: playQueuePath,
                using: configuration
            )
        }
    }

    func resetPlayQueue(queueID: Int) async throws -> PlexPlayQueuePage {
        try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            guard let playQueuePath = endpoints.playQueuePath else {
                throw PlexAPIError.missingLibraryPlayQueueFeature
            }
            return try await client.resetPlayQueue(
                queueID: queueID,
                endpointPath: playQueuePath,
                using: configuration
            )
        }
    }

    func playableDetails(for item: PlexMediaItem) async throws -> PlexMediaItem {
        if item.isPlayable {
            return item
        }
        return try await connectionStore.perform { configuration in
            try await client.fetchMediaMetadata(ratingKey: item.ratingKey, using: configuration)
        }
    }

    func isUpdatingWatchedState(for item: PlexMediaItem) -> Bool {
        watchedStateMutationRatingKeys.contains(item.ratingKey)
    }

    func supportsWatchedStateMutation(for item: PlexMediaItem) -> Bool {
        item.supportsWatchedStateMutation
            && presentedProviderConnectionKey == activeProviderConnectionKey
            && presentedProviderEndpoints?.supportsWatchedStateMutation == true
    }

    var supportsPersonalRatings: Bool {
        presentedProviderConnectionKey == activeProviderConnectionKey
            && presentedProviderEndpoints?.supportsRating == true
    }

    func supportsMetadataRefresh(for item: PlexMediaItem) -> Bool {
        item.supportsMetadataRefresh
            && presentedProviderConnectionKey == activeProviderConnectionKey
            && presentedProviderEndpoints?.supportsMetadataRefresh == true
    }

    func isUpdatingPersonalRating(for item: PlexMediaItem) -> Bool {
        personalRatingMutationRatingKeys.contains(item.ratingKey)
    }

    func isRefreshingMetadata(for item: PlexMediaItem) -> Bool {
        metadataRefreshRatingKeys.contains(item.ratingKey)
    }

    var supportsRemoveFromContinueWatching: Bool {
        presentedProviderConnectionKey == activeProviderConnectionKey
            && presentedProviderEndpoints?.supportsRemoveFromContinueWatching == true
    }

    func downloadAuthorization(
        for user: PlexAuthenticatedUser,
        library: PlexLibrary
    ) -> PlexDownloadAuthorization? {
        guard presentedProviderConnectionKey == activeProviderConnectionKey,
              let presentedProviderEndpoints else {
            return nil
        }

        return PlexDownloadAuthorization(
            user: user,
            library: library,
            providerEndpoints: presentedProviderEndpoints
        )
    }

    func downloadProviderEndpoints(
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexLibraryProviderEndpoints {
        try await libraryProviderEndpoints(using: configuration)
    }

    func resolvedLibraryProviderEndpoints(
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexLibraryProviderEndpoints {
        try await libraryProviderEndpoints(using: configuration)
    }

    func isRemovingFromContinueWatching(_ item: PlexMediaItem) -> Bool {
        continueWatchingRemovalRatingKeys.contains(item.ratingKey)
    }

    func loadLibraryProviderCapabilities() async {
        let stateID = serverStateID
        do {
            _ = try await connectionStore.perform { configuration in
                try await self.libraryProviderEndpoints(using: configuration)
            }
        } catch {
            guard serverStateID == stateID, !Task.isCancelled else { return }
            presentedProviderEndpoints = nil
            presentedProviderConnectionKey = nil
        }
    }

    @discardableResult
    func setWatched(_ watched: Bool, for item: PlexMediaItem) async throws -> PlexMediaItem {
        guard item.supportsWatchedStateMutation else {
            throw PlexBrowserMutationError.unsupportedWatchedState
        }
        guard watchedStateMutationRatingKeys.insert(item.ratingKey).inserted else {
            throw PlexBrowserMutationError.watchedStateUpdateInProgress
        }
        defer { watchedStateMutationRatingKeys.remove(item.ratingKey) }

        let refreshedItem = try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            try await self.client.setWatched(
                watched,
                ratingKey: item.ratingKey,
                endpoints: endpoints,
                using: configuration
            )
            return try await self.client.fetchMediaMetadata(
                ratingKey: item.ratingKey,
                using: configuration
            )
        }
        replaceCachedWatchedState(with: refreshedItem)
        return refreshedItem
    }

    @discardableResult
    func setPersonalRating(_ rating: Double?, for item: PlexMediaItem) async throws -> PlexMediaItem {
        guard personalRatingMutationRatingKeys.insert(item.ratingKey).inserted else {
            throw PlexBrowserMutationError.personalRatingUpdateInProgress
        }
        defer { personalRatingMutationRatingKeys.remove(item.ratingKey) }

        let refreshedItem = try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            try await self.client.setPersonalRating(
                rating,
                ratingKey: item.ratingKey,
                endpoints: endpoints,
                using: configuration
            )
            return try await self.client.fetchMediaMetadata(
                ratingKey: item.ratingKey,
                using: configuration
            )
        }
        replaceCachedUserRating(with: refreshedItem)
        return refreshedItem
    }

    func refreshMetadata(for item: PlexMediaItem) async throws {
        guard item.supportsMetadataRefresh else {
            throw PlexBrowserMutationError.unsupportedMetadataRefresh
        }
        guard metadataRefreshRatingKeys.insert(item.ratingKey).inserted else {
            throw PlexBrowserMutationError.metadataRefreshInProgress
        }
        defer { metadataRefreshRatingKeys.remove(item.ratingKey) }

        try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            try await self.client.refreshMediaMetadata(
                ratingKey: item.ratingKey,
                endpoints: endpoints,
                using: configuration
            )
        }
    }

    func removeFromContinueWatching(_ item: PlexMediaItem) async throws {
        guard continueWatchingRemovalRatingKeys.insert(item.ratingKey).inserted else {
            throw PlexBrowserMutationError.continueWatchingRemovalInProgress
        }
        defer { continueWatchingRemovalRatingKeys.remove(item.ratingKey) }

        try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            try await self.client.removeFromContinueWatching(
                ratingKey: item.ratingKey,
                endpoints: endpoints,
                using: configuration
            )
        }
        removeCachedContinueWatchingItem(ratingKey: item.ratingKey)
    }

    func markPlayedIfSupported(ratingKey: String) async throws {
        try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            guard endpoints.supportsWatchedStateMutation else {
                return
            }
            try await self.client.setWatched(
                true,
                ratingKey: ratingKey,
                endpoints: endpoints,
                using: configuration
            )
        }
    }

    func reportTimeline(
        _ update: PlexTimelineUpdate,
        accountScope: String
    ) async -> PlexTimelineResponse? {
        guard connectionStore.accountCacheScope == accountScope else { return nil }
        do {
            return try await connectionStore.perform { configuration in
                let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                guard self.connectionStore.accountCacheScope == accountScope else {
                    throw CancellationError()
                }
                guard let timelinePath = endpoints.timelinePath else {
                    throw PlexAPIError.missingLibraryTimelineFeature
                }
                return try await self.client.reportTimeline(
                    update,
                    endpointPath: timelinePath,
                    using: configuration
                )
            }
        } catch {
            // Playback must continue when timeline reporting is temporarily unavailable.
            return nil
        }
    }
}

extension PlexBrowserStore {
    var supportsCollectionManagement: Bool {
        presentedProviderConnectionKey == activeProviderConnectionKey
            && presentedProviderEndpoints?.supportsCollectionManagement == true
    }

    var supportsPlaylistCreation: Bool {
        presentedProviderConnectionKey == activeProviderConnectionKey
            && presentedProviderEndpoints?.supportsPlaylistManagement == true
    }

    func supportsPlaylistManagement(for playlist: PlexMediaItem) -> Bool {
        supportsPlaylistCreation
            && playlist.type?.lowercased() == "playlist"
            && playlist.readOnly != true
    }

    func supportsChildManagement(of parent: PlexMediaItem) -> Bool {
        switch parent.type?.lowercased() {
        case "collection":
            return supportsCollectionManagement && parent.smart != true
        case "playlist":
            return supportsPlaylistManagement(for: parent) && parent.smart != true
        default:
            return false
        }
    }

    func isManagingCollectionOrPlaylist(_ item: PlexMediaItem) -> Bool {
        collectionPlaylistMutationKeys.contains(mutationKey(for: item))
    }

    func isCreatingCollection(in library: PlexLibrary) -> Bool {
        collectionPlaylistMutationKeys.contains("collection:create:\(library.id)")
    }

    func createCollection(named title: String, in library: PlexLibrary) async throws -> PlexMediaItem {
        guard let metadataTypeID = library.type.metadataTypeID else {
            throw PlexAPIError.invalidResponse
        }
        let key = "collection:create:\(library.id)"
        return try await withCollectionPlaylistMutation(key: key) {
            let createdCollection = try await connectionStore.perform { configuration in
                let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                guard endpoints.supportsCollectionManagement,
                      let collectionPath = endpoints.collectionPath else {
                    throw PlexAPIError.libraryManagementUnavailable
                }
                return try await self.client.createCollection(
                    title: title,
                    libraryID: library.id,
                    metadataTypeID: metadataTypeID,
                    endpointPath: collectionPath,
                    using: configuration
                )
            }
            if collectionItemsByLibraryID[library.id]?.contains(where: {
                $0.ratingKey == createdCollection.ratingKey
            }) != true {
                collectionItemsByLibraryID[library.id, default: []].append(createdCollection)
                collectionTotalSizesByLibraryID[library.id] =
                    (collectionTotalSizesByLibraryID[library.id] ?? 0) + 1
            }
            await refreshCollectionsAfterConfirmedMutation(in: library)
            return collections(in: library).first {
                $0.ratingKey == createdCollection.ratingKey
            } ?? createdCollection
        }
    }

    func createCollection(
        named title: String,
        containing item: PlexMediaItem,
        in library: PlexLibrary
    ) async throws {
        let collection = try await createCollection(named: title, in: library)
        do {
            try await add(item, to: collection, in: library)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlexBrowserMutationError.collectionCreatedWithoutItem(title: collection.title)
        }
    }

    func editableCollections(in library: PlexLibrary) -> [PlexMediaItem] {
        guard supportsCollectionManagement else {
            return []
        }
        return collections(in: library).filter {
            $0.type?.lowercased() == "collection" && $0.smart != true
        }
    }

    func editablePlaylists(for item: PlexMediaItem) -> [PlexMediaItem] {
        guard let playlistMediaType = item.playlistMediaType else {
            return []
        }
        return playlists.filter {
            supportsPlaylistManagement(for: $0)
                && $0.smart != true
                && $0.playlistType?.lowercased() == playlistMediaType
        }
    }

    func add(
        _ item: PlexMediaItem,
        to collection: PlexMediaItem,
        in library: PlexLibrary
    ) async throws {
        guard editableCollections(in: library).contains(where: {
            $0.ratingKey == collection.ratingKey
        }) else {
            throw PlexBrowserMutationError.itemManagementUnavailable
        }
        try await withCollectionPlaylistMutation(key: mutationKey(for: collection)) {
            try await connectionStore.perform { configuration in
                let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                guard endpoints.supportsCollectionManagement,
                      let collectionPath = endpoints.collectionPath,
                      let serverIdentifier = configuration.serverIdentifier else {
                    throw PlexAPIError.libraryManagementUnavailable
                }
                let uri = try PlexMediaSourceURI.item(
                    item,
                    serverIdentifier: serverIdentifier,
                    providerIdentifier: endpoints.providerIdentifier
                )
                try await self.client.addItem(
                    uri: uri,
                    toCollectionID: collection.ratingKey,
                    endpointPath: collectionPath,
                    using: configuration
                )
            }
            await refreshCollectionsAfterConfirmedMutation(in: library)
            await refreshChildrenAfterConfirmedMutation(of: collection)
        }
    }

    func add(_ item: PlexMediaItem, to playlist: PlexMediaItem) async throws {
        guard editablePlaylists(for: item).contains(where: {
            $0.ratingKey == playlist.ratingKey
        }) else {
            throw PlexBrowserMutationError.itemManagementUnavailable
        }
        try await withCollectionPlaylistMutation(key: mutationKey(for: playlist)) {
            try await connectionStore.perform { configuration in
                let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                guard endpoints.supportsPlaylistManagement,
                      let playlistPath = endpoints.playlistPath else {
                    throw PlexAPIError.libraryManagementUnavailable
                }
                guard let serverIdentifier = configuration.serverIdentifier else {
                    throw PlexAPIError.missingServerIdentity
                }
                let uri = try PlexMediaSourceURI.item(item, serverIdentifier: serverIdentifier)
                try await self.client.addItem(
                    uri: uri,
                    toPlaylistID: playlist.ratingKey,
                    endpointPath: playlistPath,
                    using: configuration
                )
            }
            await refreshPlaylistsAfterConfirmedMutation()
            await refreshChildrenAfterConfirmedMutation(of: playlist)
        }
    }

    func createPlaylist(named title: String, containing item: PlexMediaItem) async throws {
        guard title.nilIfBlank != nil, item.playlistMediaType != nil else {
            throw PlexAPIError.invalidMediaTitle
        }
        let key = "playlist:create:\(item.ratingKey)"
        try await withCollectionPlaylistMutation(key: key) {
            let createdPlaylist = try await connectionStore.perform { configuration in
                let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                guard endpoints.supportsPlaylistManagement,
                      let playlistPath = endpoints.playlistPath else {
                    throw PlexAPIError.libraryManagementUnavailable
                }
                guard let serverIdentifier = configuration.serverIdentifier else {
                    throw PlexAPIError.missingServerIdentity
                }
                let uri = try PlexMediaSourceURI.item(item, serverIdentifier: serverIdentifier)
                return try await self.client.createPlaylist(
                    containingItemURI: uri,
                    endpointPath: playlistPath,
                    using: configuration
                )
            }

            do {
                try await connectionStore.perform { configuration in
                    let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                    guard endpoints.supportsPlaylistManagement,
                          let playlistPath = endpoints.playlistPath else {
                        throw PlexAPIError.libraryManagementUnavailable
                    }
                    try await self.client.renamePlaylist(
                        id: createdPlaylist.ratingKey,
                        title: title,
                        endpointPath: playlistPath,
                        using: configuration
                    )
                }
            } catch {
                try? await reloadPlaylists()
                throw PlexBrowserMutationError.playlistCreatedWithoutRequestedName
            }
            await refreshPlaylistsAfterConfirmedMutation()
        }
    }

    func renameCollection(
        _ collection: PlexMediaItem,
        to title: String,
        in library: PlexLibrary
    ) async throws {
        try await withCollectionPlaylistMutation(key: mutationKey(for: collection)) {
            try await connectionStore.perform { configuration in
                let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                guard endpoints.supportsCollectionManagement,
                      let metadataPath = endpoints.metadataPath else {
                    throw PlexAPIError.libraryManagementUnavailable
                }
                try await self.client.renameCollection(
                    id: collection.ratingKey,
                    title: title,
                    metadataEndpointPath: metadataPath,
                    using: configuration
                )
            }
            await refreshCollectionsAfterConfirmedMutation(in: library)
        }
    }

    func deleteCollection(_ collection: PlexMediaItem, in library: PlexLibrary) async throws {
        try await withCollectionPlaylistMutation(key: mutationKey(for: collection)) {
            try await connectionStore.perform { configuration in
                let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                guard endpoints.supportsCollectionManagement else {
                    throw PlexAPIError.libraryManagementUnavailable
                }
                try await self.client.deleteCollection(
                    id: collection.ratingKey,
                    libraryID: library.id,
                    using: configuration
                )
            }
            collectionItemsByLibraryID[library.id]?.removeAll {
                $0.ratingKey == collection.ratingKey
            }
            if let totalSize = collectionTotalSizesByLibraryID[library.id] {
                collectionTotalSizesByLibraryID[library.id] = max(totalSize - 1, 0)
            }
            if let childrenPath = collection.childrenPath {
                childItems[childrenPath] = nil
                childTotalSizes[childrenPath] = nil
                childErrorMessages[childrenPath] = nil
            }
        }
    }

    func renamePlaylist(_ playlist: PlexMediaItem, to title: String) async throws {
        guard supportsPlaylistManagement(for: playlist) else {
            throw PlexBrowserMutationError.itemManagementUnavailable
        }
        try await withCollectionPlaylistMutation(key: mutationKey(for: playlist)) {
            try await connectionStore.perform { configuration in
                let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                guard endpoints.supportsPlaylistManagement,
                      let playlistPath = endpoints.playlistPath else {
                    throw PlexAPIError.libraryManagementUnavailable
                }
                try await self.client.renamePlaylist(
                    id: playlist.ratingKey,
                    title: title,
                    endpointPath: playlistPath,
                    using: configuration
                )
            }
            await refreshPlaylistsAfterConfirmedMutation()
        }
    }

    func deletePlaylist(_ playlist: PlexMediaItem) async throws {
        guard supportsPlaylistManagement(for: playlist) else {
            throw PlexBrowserMutationError.itemManagementUnavailable
        }
        try await withCollectionPlaylistMutation(key: mutationKey(for: playlist)) {
            try await connectionStore.perform { configuration in
                let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                guard endpoints.supportsPlaylistManagement,
                      let playlistPath = endpoints.playlistPath else {
                    throw PlexAPIError.libraryManagementUnavailable
                }
                try await self.client.deletePlaylist(
                    id: playlist.ratingKey,
                    endpointPath: playlistPath,
                    using: configuration
                )
            }
            playlists.removeAll { $0.ratingKey == playlist.ratingKey }
            playlistsTotalSize = playlistsTotalSize.map { max($0 - 1, 0) }
            if let childrenPath = playlist.childrenPath {
                childItems[childrenPath] = nil
                childTotalSizes[childrenPath] = nil
                childErrorMessages[childrenPath] = nil
            }
        }
    }

    func canMoveChild(
        _ child: PlexMediaItem,
        in parent: PlexMediaItem,
        direction: PlexListMoveDirection
    ) -> Bool {
        guard supportsChildManagement(of: parent),
              let childrenPath = parent.childrenPath,
              let index = childItems[childrenPath]?.firstIndex(where: { $0.id == child.id }) else {
            return false
        }
        switch direction {
        case .up:
            return index > 0
        case .down:
            return index + 1 < (childItems[childrenPath]?.count ?? 0)
        }
    }

    func moveChild(
        _ child: PlexMediaItem,
        in parent: PlexMediaItem,
        direction: PlexListMoveDirection
    ) async throws {
        guard supportsChildManagement(of: parent),
              let childrenPath = parent.childrenPath,
              let siblings = childItems[childrenPath],
              let sourceIndex = siblings.firstIndex(where: { $0.id == child.id }) else {
            throw PlexBrowserMutationError.itemManagementUnavailable
        }

        let afterItem: PlexMediaItem?
        switch direction {
        case .up:
            guard sourceIndex > 0 else {
                throw PlexBrowserMutationError.invalidMove
            }
            afterItem = sourceIndex == 1 ? nil : siblings[sourceIndex - 2]
        case .down:
            guard sourceIndex + 1 < siblings.count else {
                throw PlexBrowserMutationError.invalidMove
            }
            afterItem = siblings[sourceIndex + 1]
        }

        try await withCollectionPlaylistMutation(key: mutationKey(for: parent)) {
            try await connectionStore.perform { configuration in
                switch parent.type?.lowercased() {
                case "collection":
                    let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                    guard endpoints.supportsCollectionManagement,
                          let collectionPath = endpoints.collectionPath else {
                        throw PlexAPIError.libraryManagementUnavailable
                    }
                    try await self.client.moveCollectionItem(
                        id: child.ratingKey,
                        inCollectionID: parent.ratingKey,
                        afterItemID: afterItem?.ratingKey,
                        endpointPath: collectionPath,
                        using: configuration
                    )
                case "playlist":
                    let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                    guard endpoints.supportsPlaylistManagement,
                          let playlistPath = endpoints.playlistPath else {
                        throw PlexAPIError.libraryManagementUnavailable
                    }
                    guard let playlistItemID = child.playlistItemID,
                          afterItem == nil || afterItem?.playlistItemID != nil else {
                        throw PlexAPIError.invalidResponse
                    }
                    try await self.client.movePlaylistItem(
                        playlistItemID: playlistItemID,
                        inPlaylistID: parent.ratingKey,
                        afterPlaylistItemID: afterItem?.playlistItemID,
                        endpointPath: playlistPath,
                        using: configuration
                    )
                default:
                    throw PlexBrowserMutationError.itemManagementUnavailable
                }
            }
            await refreshChildrenAfterConfirmedMutation(of: parent)
        }
    }

    func removeChild(_ child: PlexMediaItem, from parent: PlexMediaItem) async throws {
        guard supportsChildManagement(of: parent) else {
            throw PlexBrowserMutationError.itemManagementUnavailable
        }
        try await withCollectionPlaylistMutation(key: mutationKey(for: parent)) {
            try await connectionStore.perform { configuration in
                switch parent.type?.lowercased() {
                case "collection":
                    let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                    guard endpoints.supportsCollectionManagement,
                          let collectionPath = endpoints.collectionPath else {
                        throw PlexAPIError.libraryManagementUnavailable
                    }
                    try await self.client.removeCollectionItem(
                        id: child.ratingKey,
                        fromCollectionID: parent.ratingKey,
                        endpointPath: collectionPath,
                        using: configuration
                    )
                case "playlist":
                    let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                    guard endpoints.supportsPlaylistManagement,
                          let playlistPath = endpoints.playlistPath else {
                        throw PlexAPIError.libraryManagementUnavailable
                    }
                    guard let playlistItemID = child.playlistItemID else {
                        throw PlexAPIError.invalidResponse
                    }
                    try await self.client.removePlaylistItem(
                        playlistItemID: playlistItemID,
                        fromPlaylistID: parent.ratingKey,
                        endpointPath: playlistPath,
                        using: configuration
                    )
                default:
                    throw PlexBrowserMutationError.itemManagementUnavailable
                }
            }
            await refreshChildrenAfterConfirmedMutation(of: parent)
        }
    }

    func advertisedLibraryProviderEndpoints(
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexLibraryProviderEndpoints {
        try await libraryProviderEndpoints(using: configuration)
    }
}

private extension PlexBrowserStore {
    func withCollectionPlaylistMutation<T>(
        key: String,
        operation: () async throws -> T
    ) async throws -> T {
        guard collectionPlaylistMutationKeys.insert(key).inserted else {
            throw PlexBrowserMutationError.itemManagementInProgress
        }
        defer { collectionPlaylistMutationKeys.remove(key) }
        return try await operation()
    }

    func mutationKey(for item: PlexMediaItem) -> String {
        "\(item.type?.lowercased() ?? "item"):\(item.ratingKey)"
    }

    func reloadCollections(in library: PlexLibrary) async throws {
        let page = try await connectionStore.perform { configuration in
            try await self.client.fetchCollectionsPage(
                libraryID: library.id,
                using: configuration,
                start: 0,
                size: self.pageSize
            )
        }
        collectionItemsByLibraryID[library.id] = page.items
        collectionTotalSizesByLibraryID[library.id] = page.totalSize ?? page.items.count
        collectionErrorMessagesByLibraryID[library.id] = nil
    }

    func reloadPlaylists() async throws {
        let page = try await connectionStore.perform { configuration in
            let endpoints = try await self.libraryProviderEndpoints(using: configuration)
            guard let playlistPath = endpoints.playlistPath else {
                throw PlexAPIError.missingLibraryPlaylistFeature
            }
            return try await self.client.fetchPlaylistsPage(
                endpointPath: playlistPath,
                using: configuration,
                start: 0,
                size: self.pageSize
            )
        }
        playlists = page.items
        playlistsTotalSize = page.totalSize ?? page.items.count
        playlistsErrorMessage = nil
    }

    func reloadChildren(of parent: PlexMediaItem) async throws {
        guard let childrenPath = parent.childrenPath else {
            throw PlexAPIError.invalidResponse
        }
        let page = try await fetchChildrenPage(of: parent, start: 0)
        childItems[childrenPath] = page.items
        childTotalSizes[childrenPath] = page.totalSize ?? page.items.count
        childErrorMessages[childrenPath] = nil
    }

    func refreshCollectionsAfterConfirmedMutation(in library: PlexLibrary) async {
        do {
            try await reloadCollections(in: library)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            collectionErrorMessagesByLibraryID[library.id] = error.localizedDescription
        }
    }

    func refreshPlaylistsAfterConfirmedMutation() async {
        do {
            try await reloadPlaylists()
        } catch {
            guard !Task.isCancelled else {
                return
            }
            playlistsErrorMessage = error.localizedDescription
        }
    }

    func refreshChildrenAfterConfirmedMutation(of parent: PlexMediaItem) async {
        guard let childrenPath = parent.childrenPath else {
            return
        }
        do {
            try await reloadChildren(of: parent)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            childErrorMessages[childrenPath] = error.localizedDescription
        }
    }

    func libraryProviderEndpoints(
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexLibraryProviderEndpoints {
        let stateID = serverStateID
        let connectionKey = providerConnectionKey(
            serverIdentifier: configuration.serverIdentifier,
            serverURL: configuration.serverURL,
            authenticationCacheScope: configuration.authenticationCacheScope
        )

        if let endpoints = providerEndpointsByConnectionKey[connectionKey] {
            presentedProviderEndpoints = endpoints
            presentedProviderConnectionKey = connectionKey
            return endpoints
        }
        if let task = providerEndpointTasksByConnectionKey[connectionKey] {
            let endpoints = try await task.value
            try Task.checkCancellation()
            guard serverStateID == stateID else { throw CancellationError() }
            presentedProviderEndpoints = endpoints
            presentedProviderConnectionKey = connectionKey
            return endpoints
        }

        let task = Task { @MainActor in
            try await client.fetchLibraryProviderEndpoints(using: configuration)
        }
        providerEndpointTasksByConnectionKey[connectionKey] = task
        defer {
            if serverStateID == stateID {
                providerEndpointTasksByConnectionKey[connectionKey] = nil
            }
        }

        let endpoints = try await task.value
        try Task.checkCancellation()
        guard serverStateID == stateID else { throw CancellationError() }
        providerEndpointsByConnectionKey[connectionKey] = endpoints
        presentedProviderEndpoints = endpoints
        presentedProviderConnectionKey = connectionKey
        return endpoints
    }

    var activeProviderConnectionKey: String? {
        guard let serverURL = connectionStore.resolvedServerURL else {
            return nil
        }
        return providerConnectionKey(
            serverIdentifier: connectionStore.activeConnection?.serverID
                ?? connectionStore.settings.selectedServerIdentifier,
            serverURL: serverURL,
            authenticationCacheScope: PlexConnectionConfiguration.authenticationCacheScope(
                for: connectionStore.settings.trimmedServerToken
            )
        )
    }

    func providerConnectionKey(
        serverIdentifier: String?,
        serverURL: URL,
        authenticationCacheScope: String
    ) -> String {
        [serverIdentifier ?? "", serverURL.absoluteString, authenticationCacheScope]
            .joined(separator: "|")
    }

    func replaceCachedWatchedState(with refreshedItem: PlexMediaItem) {
        libraryItems = libraryItems.mapValues {
            replacingWatchedState(in: $0, with: refreshedItem)
        }

        homeState.hubs = homeState.hubs.map { hub in
            var updatedHub = hub
            updatedHub.metadata = replacingWatchedState(in: hub.metadata, with: refreshedItem)
            return updatedHub
        }
        homeState.itemsByHubPath = homeState.itemsByHubPath.mapValues {
            replacingWatchedState(in: $0, with: refreshedItem)
        }
        globalSearchStore.replaceCachedWatchedState(with: refreshedItem)
        replaceCachedRelatedWatchedState(with: refreshedItem)
        replaceCachedMediaExtrasWatchedState(with: refreshedItem)
        collectionItemsByLibraryID = collectionItemsByLibraryID.mapValues {
            replacingWatchedState(in: $0, with: refreshedItem)
        }
        playlists = replacingWatchedState(in: playlists, with: refreshedItem)
        childItems = childItems.mapValues {
            replacingWatchedState(in: $0, with: refreshedItem)
        }
    }

    func replaceCachedUserRating(with refreshedItem: PlexMediaItem) {
        libraryItems = libraryItems.mapValues {
            replacingUserRating(in: $0, with: refreshedItem)
        }

        homeState.hubs = homeState.hubs.map { hub in
            var updatedHub = hub
            updatedHub.metadata = replacingUserRating(in: hub.metadata, with: refreshedItem)
            return updatedHub
        }
        homeState.itemsByHubPath = homeState.itemsByHubPath.mapValues {
            replacingUserRating(in: $0, with: refreshedItem)
        }
        globalSearchStore.replaceCachedUserRating(with: refreshedItem)
        replaceCachedRelatedUserRating(with: refreshedItem)
        replaceCachedMediaExtrasUserRating(with: refreshedItem)
        collectionItemsByLibraryID = collectionItemsByLibraryID.mapValues {
            replacingUserRating(in: $0, with: refreshedItem)
        }
        playlists = replacingUserRating(in: playlists, with: refreshedItem)
        childItems = childItems.mapValues {
            replacingUserRating(in: $0, with: refreshedItem)
        }
    }

    func removeCachedContinueWatchingItem(ratingKey: String) {
        let continueWatchingPaths = Set(
            homeState.hubs
                .filter(\.isContinueWatching)
                .compactMap(\.key)
        )

        homeState.hubs = homeState.hubs.map { hub in
            guard hub.isContinueWatching else {
                return hub
            }
            var updatedHub = hub
            updatedHub.metadata.removeAll { $0.ratingKey == ratingKey }
            return updatedHub
        }

        for path in continueWatchingPaths {
            let removedCount = homeState.itemsByHubPath[path]?.count(where: {
                $0.ratingKey == ratingKey
            }) ?? 0
            homeState.itemsByHubPath[path]?.removeAll { $0.ratingKey == ratingKey }
            if let totalSize = homeState.totalSizesByHubPath[path], removedCount > 0 {
                homeState.totalSizesByHubPath[path] = max(totalSize - removedCount, 0)
            }
        }
    }

    func replacingWatchedState(
        in items: [PlexMediaItem],
        with refreshedItem: PlexMediaItem
    ) -> [PlexMediaItem] {
        items.map { item in
            guard item.ratingKey == refreshedItem.ratingKey else {
                return item
            }
            return item.mergingWatchedState(from: refreshedItem)
        }
    }

    func replacingUserRating(
        in items: [PlexMediaItem],
        with refreshedItem: PlexMediaItem
    ) -> [PlexMediaItem] {
        items.map { item in
            guard item.ratingKey == refreshedItem.ratingKey else {
                return item
            }
            return item.mergingUserRating(from: refreshedItem)
        }
    }

    private func libraryBrowseDefinition(
        for library: PlexLibrary
    ) async throws -> PlexLibraryBrowseDefinition {
        if let definition = libraryBrowseDefinitions[library.id] {
            return definition
        }
        if let task = libraryBrowseDefinitionTasks[library.id] {
            return try await task.value
        }
        let task = Task { @MainActor in
            try await connectionStore.perform { configuration in
                let endpoints = try await self.libraryProviderEndpoints(using: configuration)
                guard let route = endpoints.browseRoute(for: library.id) else {
                    throw PlexAPIError.missingLibraryBrowseRoute
                }
                return try await client.fetchLibraryBrowseDefinition(
                    sectionPath: route.sectionPath,
                    contentPath: route.contentPath,
                    using: configuration
                )
            }
        }
        libraryBrowseDefinitionTasks[library.id] = task
        defer { libraryBrowseDefinitionTasks[library.id] = nil }

        let definition = try await task.value
        libraryBrowseDefinitions[library.id] = definition
        return definition
    }

    private func fetchPage(
        request: PlexLibraryRequest,
        definition: PlexLibraryBrowseDefinition,
        start: Int
    ) async throws -> PlexMediaPage {
        let selectedDefinition = try definition.selecting(request.browseOptions.contentTypePath)
        return try await connectionStore.perform { configuration in
            try await client.fetchMediaPage(
                contentPath: selectedDefinition.contentPath,
                using: configuration,
                start: start,
                size: pageSize,
                searchQuery: request.searchQuery,
                browseOptions: request.browseOptions
            )
        }
    }

    private func fetchChildrenPage(of item: PlexMediaItem, start: Int) async throws -> PlexMediaPage {
        try await connectionStore.perform { configuration in
            try await client.fetchMediaChildren(
                of: item,
                using: configuration,
                start: start,
                size: pageSize
            )
        }
    }

}

enum PlexBrowserMutationError: LocalizedError {
    case unsupportedWatchedState
    case watchedStateUpdateInProgress
    case personalRatingUpdateInProgress
    case unsupportedMetadataRefresh
    case metadataRefreshInProgress
    case continueWatchingRemovalInProgress
    case itemManagementUnavailable
    case itemManagementInProgress
    case invalidMove
    case playlistCreatedWithoutRequestedName
    case collectionCreatedWithoutItem(title: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedWatchedState:
            "Plex does not expose watched status for this item type."
        case .watchedStateUpdateInProgress:
            "This item's watched status is already being updated."
        case .personalRatingUpdateInProgress:
            "This item's personal rating is already being updated."
        case .unsupportedMetadataRefresh:
            "Plex does not expose metadata refresh for this item type."
        case .metadataRefreshInProgress:
            "Plex is already starting a metadata refresh for this item."
        case .continueWatchingRemovalInProgress:
            "This item is already being removed from Continue Watching."
        case .itemManagementUnavailable:
            "Plex does not allow this collection or playlist to be changed."
        case .itemManagementInProgress:
            "This collection or playlist is already being changed."
        case .invalidMove:
            "That item cannot move farther in this direction."
        case .playlistCreatedWithoutRequestedName:
            "Plex created the playlist but did not apply its requested name. Rename it from Playlists."
        case let .collectionCreatedWithoutItem(title):
            "Plex created \(title), but the item was not added. You can add it to that collection after retrying the connection."
        }
    }
}
