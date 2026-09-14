import PlexModels
import Foundation

extension PlexAPIClient {
    func createCinemaPlayQueue(
        for item: PlexMediaItem,
        extrasPrefixCount: Int,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexPlaybackQueue {
        guard let serverIdentifier = configuration.serverIdentifier else {
            throw PlexAPIError.missingServerIdentity
        }
        let queueRequest = try PlexCinemaPlayQueueRequest(
            item: item,
            extrasPrefixCount: extrasPrefixCount,
            serverIdentifier: serverIdentifier
        )
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }

        components.queryItems = (components.queryItems ?? []) + queueRequest.queryItems

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            method: "POST",
            accept: "application/json",
            token: configuration.token
        )
        let page = try await playQueuePage(for: request)
        guard page.selectedItemID?.nilIfBlank != nil else {
            throw PlexAPIError.invalidPlayQueue
        }
        return try PlexPlaybackQueue(
            page: page,
            selectedRatingKey: item.ratingKey,
            purpose: .cinemaPreplay(primaryRatingKey: item.ratingKey)
        )
    }

    func createContinuousPlayQueue(
        for item: PlexMediaItem,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexPlaybackQueue {
        guard let serverIdentifier = configuration.serverIdentifier else {
            throw PlexAPIError.missingServerIdentity
        }
        let queueRequest = try PlexContinuousPlayQueueRequest(
            item: item,
            serverIdentifier: serverIdentifier
        )
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }

        components.queryItems = (components.queryItems ?? []) + queueRequest.queryItems

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            method: "POST",
            accept: "application/json",
            token: configuration.token
        )
        let page = try await playQueuePage(for: request)
        return try PlexPlaybackQueue(page: page, selectedRatingKey: item.ratingKey)
    }

    func fetchPlayQueuePage(
        queueID: Int,
        endpointPath: String,
        centeredOn playQueueItemID: String,
        window: Int = 50,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexPlayQueuePage {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath,
            appendingPathComponent: String(queueID)
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "center", value: playQueueItemID),
            URLQueryItem(name: "window", value: String(max(window, 1))),
            URLQueryItem(name: "includeBefore", value: "1"),
            URLQueryItem(name: "includeAfter", value: "1"),
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            accept: "application/json",
            token: configuration.token
        )
        return try await playQueuePage(for: request)
    }

    func addToPlayQueue(
        _ item: PlexMediaItem,
        queueID: Int,
        insertion: PlexPlayQueueInsertion,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexPlayQueuePage {
        guard let serverIdentifier = configuration.serverIdentifier else {
            throw PlexAPIError.missingServerIdentity
        }
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath,
            appendingPathComponent: String(queueID)
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        let sourceURI = try PlexMediaSourceURI.item(
            item,
            serverIdentifier: serverIdentifier
        )
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "uri", value: sourceURI),
            URLQueryItem(name: "next", value: insertion.queryValue),
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            method: "PUT",
            accept: "application/json",
            token: configuration.token
        )
        return try await playQueuePage(for: request)
    }

    func setPlayQueueShuffled(
        _ shuffled: Bool,
        queueID: Int,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexPlayQueuePage {
        let mutation = try PlexPlayQueueMutationRequest(
            queueID: queueID,
            mutation: .shuffled(shuffled)
        )
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath,
            appendingPathComponents: mutation.endpointPathComponents
        ) else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: endpoint,
            method: "PUT",
            accept: "application/json",
            token: configuration.token
        )
        return try await playQueuePage(for: request)
    }

    func removePlayQueueItem(
        queueID: Int,
        playQueueItemID: String,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexPlayQueuePage {
        let mutation = try PlexPlayQueueItemMutationRequest(
            queueID: queueID,
            mutation: .remove(playQueueItemID: playQueueItemID)
        )
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath,
            appendingPathComponents: mutation.endpointPathComponents
        ) else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: endpoint,
            method: mutation.method,
            accept: "application/json",
            token: configuration.token
        )
        return try await playQueuePage(for: request)
    }

    func movePlayQueueItem(
        queueID: Int,
        move: PlexPlayQueueItemMove,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexPlayQueuePage {
        let mutation = try PlexPlayQueueItemMutationRequest(
            queueID: queueID,
            mutation: .move(move)
        )
        guard let endpoint = PlexURLBuilder.endpointURL(
                  serverURL: configuration.serverURL,
                  path: endpointPath,
                  appendingPathComponents: mutation.endpointPathComponents
              ),
              var components = URLComponents(
                  url: endpoint,
                  resolvingAgainstBaseURL: false
              ) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = (components.queryItems ?? []) + mutation.queryItems
        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            method: mutation.method,
            accept: "application/json",
            token: configuration.token
        )
        return try await playQueuePage(for: request)
    }

    func resetPlayQueue(
        queueID: Int,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexPlayQueuePage {
        let mutation = try PlexPlayQueueMutationRequest(
            queueID: queueID,
            mutation: .reset
        )
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath,
            appendingPathComponents: mutation.endpointPathComponents
        ) else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: endpoint,
            method: "PUT",
            accept: "application/json",
            token: configuration.token
        )
        return try await playQueuePage(for: request)
    }

    func setWatched(
        _ watched: Bool,
        ratingKey: String,
        endpoints: PlexLibraryProviderEndpoints,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        let parameters = try PlexWatchedStateRequestParameters(
            watched: watched,
            ratingKey: ratingKey,
            endpoints: endpoints
        )
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: parameters.endpointPath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = (components.queryItems ?? []) + parameters.queryItems

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            method: "PUT",
            accept: "application/json",
            token: configuration.token
        )
        _ = try await responseData(for: request)
    }

    private func playQueuePage(for request: URLRequest) async throws -> PlexPlayQueuePage {
        let data = try await data(for: request)
        do {
            let envelope = try JSONDecoder().decode(PlexPlayQueueEnvelope.self, from: data)
            return try envelope.mediaContainer.page()
        } catch let error as PlexAPIError {
            throw error
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

}
