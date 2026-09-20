import PlexClientKit
import Foundation

extension PlexBrowserStore {
    func filterValues(for filter: PlexLibraryFilterDefinition) -> [PlexLibraryFilterValue] {
        guard let cacheKey = currentFilterValueCacheKey(for: filter) else {
            return []
        }
        return libraryFilterValuesByCacheKey[cacheKey] ?? []
    }

    func isLoadingFilterValues(for filter: PlexLibraryFilterDefinition) -> Bool {
        guard let cacheKey = currentFilterValueCacheKey(for: filter) else {
            return false
        }
        return loadingLibraryFilterValueKeys.contains(cacheKey)
    }

    func hasLoadedFilterValues(for filter: PlexLibraryFilterDefinition) -> Bool {
        guard let cacheKey = currentFilterValueCacheKey(for: filter) else {
            return false
        }
        return libraryFilterValuesByCacheKey[cacheKey] != nil
    }

    func filterValuesErrorMessage(for filter: PlexLibraryFilterDefinition) -> String? {
        guard let cacheKey = currentFilterValueCacheKey(for: filter) else {
            return nil
        }
        return libraryFilterValueErrorMessages[cacheKey]
    }

    func loadFilterValues(
        for filter: PlexLibraryFilterDefinition,
        forceRefresh: Bool = false
    ) async {
        guard filter.valuesPath != nil,
              let initialCacheKey = currentFilterValueCacheKey(for: filter),
              !loadingLibraryFilterValueKeys.contains(initialCacheKey) else {
            return
        }
        if !forceRefresh, libraryFilterValuesByCacheKey[initialCacheKey] != nil {
            return
        }

        loadingLibraryFilterValueKeys.insert(initialCacheKey)
        defer { loadingLibraryFilterValueKeys.remove(initialCacheKey) }

        do {
            let result = try await connectionStore.perform { configuration in
                let values = try await self.client.fetchLibraryFilterValues(
                    for: filter,
                    using: configuration
                )
                let cacheKey = Self.filterValueCacheKey(
                    filter: filter,
                    serverIdentifier: configuration.serverIdentifier,
                    serverURL: configuration.serverURL,
                    authenticationCacheScope: configuration.authenticationCacheScope
                )
                return (cacheKey, values)
            }
            libraryFilterValuesByCacheKey[result.0] = result.1
            libraryFilterValueErrorMessages[result.0] = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            libraryFilterValueErrorMessages[initialCacheKey] = error.localizedDescription
        }
    }
}

private extension PlexBrowserStore {
    func currentFilterValueCacheKey(for filter: PlexLibraryFilterDefinition) -> String? {
        guard let serverURL = connectionStore.resolvedServerURL else {
            return nil
        }
        return Self.filterValueCacheKey(
            filter: filter,
            serverIdentifier: connectionStore.activeConnection?.serverID
                ?? connectionStore.settings.selectedServerIdentifier,
            serverURL: serverURL,
            authenticationCacheScope: PlexConnectionConfiguration.authenticationCacheScope(
                for: connectionStore.settings.trimmedServerToken
            )
        )
    }

    static func filterValueCacheKey(
        filter: PlexLibraryFilterDefinition,
        serverIdentifier: String?,
        serverURL: URL,
        authenticationCacheScope: String
    ) -> String {
        [
            serverIdentifier ?? "",
            serverURL.absoluteString,
            authenticationCacheScope,
            filter.valuesPath ?? "",
        ].joined(separator: "|")
    }
}
