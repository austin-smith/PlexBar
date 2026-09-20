import PlexClientKit
import PlexModels
import Foundation

extension PlexBrowserStore {
    func searchAllLibraries(query: String, limit: Int = 12) async throws -> [PlexHub] {
        try await connectionStore.perform { configuration in
            let endpoints = try await self.advertisedLibraryProviderEndpoints(
                using: configuration
            )
            guard let searchPath = endpoints.searchPath else {
                throw PlexAPIError.missingLibrarySearchFeature
            }
            return try await client.fetchSearchHubs(
                query: query,
                endpointPath: searchPath,
                using: configuration,
                limit: limit
            )
        }
    }

    func globalSearchHubPage(
        path: String,
        start: Int,
        size: Int
    ) async throws -> PlexMediaPage {
        try await connectionStore.perform { configuration in
            try await client.fetchMediaPage(
                contentPath: path,
                using: configuration,
                start: start,
                size: size
            )
        }
    }
}
