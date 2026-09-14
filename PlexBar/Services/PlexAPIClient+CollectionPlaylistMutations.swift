import PlexModels
import Foundation

extension PlexAPIClient {
    func createCollection(
        title: String,
        libraryID: String,
        metadataTypeID: Int,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexMediaItem {
        let title = try validatedMediaTitle(title)
        let data = try await performMediaMutation(
            path: endpointPath,
            method: "POST",
            queryItems: [
                URLQueryItem(name: "sectionId", value: libraryID),
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "smart", value: "0"),
                URLQueryItem(name: "type", value: String(metadataTypeID)),
            ],
            configuration: configuration
        )
        return try decodedMutationItem(from: data)
    }

    func renameCollection(
        id: String,
        title: String,
        metadataEndpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        _ = try await performMediaMutation(
            path: metadataEndpointPath,
            appendingPathComponents: [id],
            method: "PUT",
            queryItems: [URLQueryItem(name: "title", value: try validatedMediaTitle(title))],
            configuration: configuration
        )
    }

    func deleteCollection(
        id: String,
        libraryID: String,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        _ = try await performMediaMutation(
            path: "/library/sections/\(libraryID)/collection/\(id)",
            method: "DELETE",
            configuration: configuration
        )
    }

    func addItem(
        uri: String,
        toCollectionID collectionID: String,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        _ = try await performMediaMutation(
            path: endpointPath,
            appendingPathComponents: [collectionID, "items"],
            method: "PUT",
            queryItems: [URLQueryItem(name: "uri", value: uri)],
            configuration: configuration
        )
    }

    func removeCollectionItem(
        id: String,
        fromCollectionID collectionID: String,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        _ = try await performMediaMutation(
            path: endpointPath,
            appendingPathComponents: [collectionID, "items", id],
            method: "PUT",
            configuration: configuration
        )
    }

    func moveCollectionItem(
        id: String,
        inCollectionID collectionID: String,
        afterItemID: String?,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        _ = try await performMediaMutation(
            path: endpointPath,
            appendingPathComponents: [collectionID, "items", id, "move"],
            method: "PUT",
            queryItems: afterItemID.map { [URLQueryItem(name: "after", value: $0)] } ?? [],
            configuration: configuration
        )
    }

    func renamePlaylist(
        id: String,
        title: String,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        _ = try await performMediaMutation(
            path: endpointPath,
            appendingPathComponents: [id],
            method: "PUT",
            queryItems: [URLQueryItem(name: "title", value: try validatedMediaTitle(title))],
            configuration: configuration
        )
    }

    func createPlaylist(
        containingItemURI uri: String,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexMediaItem {
        let data = try await performMediaMutation(
            path: endpointPath,
            method: "POST",
            queryItems: [URLQueryItem(name: "uri", value: uri)],
            configuration: configuration
        )
        return try decodedMutationItem(from: data)
    }

    func addItem(
        uri: String,
        toPlaylistID playlistID: String,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        _ = try await performMediaMutation(
            path: endpointPath,
            appendingPathComponents: [playlistID, "items"],
            method: "PUT",
            queryItems: [URLQueryItem(name: "uri", value: uri)],
            configuration: configuration
        )
    }

    func deletePlaylist(
        id: String,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        _ = try await performMediaMutation(
            path: endpointPath,
            appendingPathComponents: [id],
            method: "DELETE",
            configuration: configuration
        )
    }

    func removePlaylistItem(
        playlistItemID: String,
        fromPlaylistID playlistID: String,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        _ = try await performMediaMutation(
            path: endpointPath,
            appendingPathComponents: [playlistID, "items", playlistItemID],
            method: "DELETE",
            configuration: configuration
        )
    }

    func movePlaylistItem(
        playlistItemID: String,
        inPlaylistID playlistID: String,
        afterPlaylistItemID: String?,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        _ = try await performMediaMutation(
            path: endpointPath,
            appendingPathComponents: [playlistID, "items", playlistItemID, "move"],
            method: "PUT",
            queryItems: afterPlaylistItemID.map { [URLQueryItem(name: "after", value: $0)] } ?? [],
            configuration: configuration
        )
    }
}

private extension PlexAPIClient {
    func performMediaMutation(
        path: String,
        appendingPathComponents: [String] = [],
        method: String,
        queryItems: [URLQueryItem] = [],
        configuration: PlexConnectionConfiguration
    ) async throws -> Data {
        let endpoint = appendingPathComponents.isEmpty
            ? PlexURLBuilder.endpointURL(serverURL: configuration.serverURL, path: path)
            : PlexURLBuilder.endpointURL(
                serverURL: configuration.serverURL,
                path: path,
                appendingPathComponents: appendingPathComponents
            )
        guard let endpoint,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            method: method,
            accept: "application/json",
            token: configuration.token
        )
        return try await data(for: request)
    }

    func validatedMediaTitle(_ title: String) throws -> String {
        guard let title = title.nilIfBlank else {
            throw PlexAPIError.invalidMediaTitle
        }
        return title
    }

    func decodedMutationItem(from data: Data) throws -> PlexMediaItem {
        do {
            guard let item = try JSONDecoder()
                .decode(PlexMediaEnvelope.self, from: data)
                .mediaContainer
                .metadata
                .first else {
                throw PlexAPIError.invalidResponse
            }
            return item
        } catch let error as PlexAPIError {
            throw error
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }
}
