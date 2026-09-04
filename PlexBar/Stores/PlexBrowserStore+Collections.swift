import Foundation

extension PlexBrowserStore {
    func collections(in library: PlexLibrary) -> [PlexMediaItem] {
        collectionItemsByLibraryID[library.id] ?? []
    }

    func isLoadingCollections(in library: PlexLibrary) -> Bool {
        loadingCollectionLibraryIDs.contains(library.id)
    }

    func collectionsErrorMessage(in library: PlexLibrary) -> String? {
        collectionErrorMessagesByLibraryID[library.id]
    }

    func hasMoreCollections(in library: PlexLibrary) -> Bool {
        let itemCount = collectionItemsByLibraryID[library.id]?.count ?? 0
        return itemCount < (collectionTotalSizesByLibraryID[library.id] ?? itemCount)
    }

    func loadCollections(in library: PlexLibrary, forceRefresh: Bool = false) async {
        guard !loadingCollectionLibraryIDs.contains(library.id) else {
            return
        }
        if !forceRefresh, collectionItemsByLibraryID[library.id] != nil {
            return
        }

        loadingCollectionLibraryIDs.insert(library.id)
        defer { loadingCollectionLibraryIDs.remove(library.id) }

        do {
            let page = try await fetchCollectionsPage(libraryID: library.id, start: 0)
            collectionItemsByLibraryID[library.id] = page.items
            collectionTotalSizesByLibraryID[library.id] = page.totalSize ?? page.items.count
            collectionErrorMessagesByLibraryID[library.id] = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            collectionErrorMessagesByLibraryID[library.id] = error.localizedDescription
        }
    }

    func loadMoreCollectionsIfNeeded(
        in library: PlexLibrary,
        currentItem: PlexMediaItem
    ) async {
        guard collectionItemsByLibraryID[library.id]?.last?.id == currentItem.id,
              hasMoreCollections(in: library),
              !loadingCollectionLibraryIDs.contains(library.id) else {
            return
        }

        loadingCollectionLibraryIDs.insert(library.id)
        defer { loadingCollectionLibraryIDs.remove(library.id) }

        do {
            let existingItems = collectionItemsByLibraryID[library.id] ?? []
            let page = try await fetchCollectionsPage(
                libraryID: library.id,
                start: existingItems.count
            )
            let existingIDs = Set(existingItems.map(\.id))
            collectionItemsByLibraryID[library.id] = existingItems
                + page.items.filter { !existingIDs.contains($0.id) }
            collectionTotalSizesByLibraryID[library.id] = page.totalSize
                ?? collectionTotalSizesByLibraryID[library.id]
            collectionErrorMessagesByLibraryID[library.id] = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            collectionErrorMessagesByLibraryID[library.id] = error.localizedDescription
        }
    }

    func loadPlaylists(forceRefresh: Bool = false) async {
        guard !isLoadingPlaylists else {
            return
        }
        if !forceRefresh, playlistsTotalSize != nil {
            return
        }

        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }

        do {
            let page = try await fetchPlaylistsPage(start: 0)
            playlists = page.items
            playlistsTotalSize = page.totalSize ?? page.items.count
            playlistsErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            playlistsErrorMessage = error.localizedDescription
        }
    }

    func loadMorePlaylistsIfNeeded(currentItem: PlexMediaItem) async {
        guard playlists.last?.id == currentItem.id,
              playlists.count < (playlistsTotalSize ?? playlists.count),
              !isLoadingPlaylists else {
            return
        }

        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }

        do {
            let page = try await fetchPlaylistsPage(start: playlists.count)
            let existingIDs = Set(playlists.map(\.id))
            playlists += page.items.filter { !existingIDs.contains($0.id) }
            playlistsTotalSize = page.totalSize ?? playlistsTotalSize
            playlistsErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            playlistsErrorMessage = error.localizedDescription
        }
    }
}

private extension PlexBrowserStore {
    func fetchCollectionsPage(
        libraryID: String,
        start: Int
    ) async throws -> PlexMediaPage {
        try await connectionStore.perform { configuration in
            try await client.fetchCollectionsPage(
                libraryID: libraryID,
                using: configuration,
                start: start,
                size: pageSize
            )
        }
    }

    func fetchPlaylistsPage(start: Int) async throws -> PlexMediaPage {
        try await connectionStore.perform { configuration in
            let endpoints = try await self.resolvedLibraryProviderEndpoints(using: configuration)
            guard let playlistPath = endpoints.playlistPath else {
                throw PlexAPIError.missingLibraryPlaylistFeature
            }
            return try await client.fetchPlaylistsPage(
                endpointPath: playlistPath,
                using: configuration,
                start: start,
                size: pageSize
            )
        }
    }
}
