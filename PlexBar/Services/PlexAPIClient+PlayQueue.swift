import Foundation

extension PlexAPIClient {
    func createCinemaPlayQueue(
        for item: PlexMediaItem,
        extrasPrefixCount: Int,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexPlaybackQueue {
        guard item.type?.lowercased() == "movie",
              (0...5).contains(extrasPrefixCount),
              let itemKey = item.key?.nilIfBlank,
              itemKey.hasPrefix("/") else {
            throw PlexAPIError.invalidPlayQueue
        }
        guard let serverIdentifier = configuration.serverIdentifier else {
            throw PlexAPIError.missingServerIdentity
        }
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }

        let sourceURI = try PlexMediaSourceURI.item(
            item,
            serverIdentifier: serverIdentifier
        )
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "uri", value: sourceURI),
            URLQueryItem(name: "type", value: PlexContinuousPlayQueueType.video.rawValue),
            URLQueryItem(name: "key", value: itemKey),
            URLQueryItem(name: "shuffle", value: "0"),
            URLQueryItem(name: "repeat", value: "0"),
            URLQueryItem(name: "continuous", value: "0"),
            URLQueryItem(name: "extrasPrefixCount", value: String(extrasPrefixCount)),
        ]

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
        guard let queueType = item.continuousPlayQueueType,
              let itemKey = item.key?.nilIfBlank,
              itemKey.hasPrefix("/") else {
            throw PlexAPIError.invalidPlayQueue
        }
        guard let serverIdentifier = configuration.serverIdentifier else {
            throw PlexAPIError.missingServerIdentity
        }
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }

        let sourceURI = try PlexMediaSourceURI.item(
            item,
            serverIdentifier: serverIdentifier
        )
        var queueQueryItems = [
            URLQueryItem(name: "uri", value: sourceURI),
            URLQueryItem(name: "type", value: queueType.rawValue),
            URLQueryItem(name: "shuffle", value: "0"),
            URLQueryItem(name: "repeat", value: "0"),
            URLQueryItem(name: "continuous", value: "1"),
        ]
        if item.continuousPlayQueueUsesOnDeck {
            queueQueryItems.append(URLQueryItem(name: "onDeck", value: "1"))
        } else {
            queueQueryItems.append(URLQueryItem(name: "key", value: itemKey))
        }
        components.queryItems = (components.queryItems ?? []) + queueQueryItems

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
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath,
            appendingPathComponents: [
                String(queueID),
                shuffled ? "shuffle" : "unshuffle",
            ]
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
        guard queueID > 0,
              isValidPlayQueueIdentifier(playQueueItemID),
              let endpoint = PlexURLBuilder.endpointURL(
                  serverURL: configuration.serverURL,
                  path: endpointPath,
                  appendingPathComponents: [
                      String(queueID),
                      "items",
                      playQueueItemID,
                  ]
              ) else {
            throw PlexAPIError.invalidPlayQueue
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: endpoint,
            method: "DELETE",
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
        guard queueID > 0,
              isValidPlayQueueIdentifier(move.playQueueItemID),
              isValidPlayQueueIdentifier(move.afterPlayQueueItemID),
              move.playQueueItemID != move.afterPlayQueueItemID,
              let endpoint = PlexURLBuilder.endpointURL(
                  serverURL: configuration.serverURL,
                  path: endpointPath,
                  appendingPathComponents: [
                      String(queueID),
                      "items",
                      move.playQueueItemID,
                      "move",
                  ]
              ),
              var components = URLComponents(
                  url: endpoint,
                  resolvingAgainstBaseURL: false
              ) else {
            throw PlexAPIError.invalidPlayQueue
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "after", value: move.afterPlayQueueItemID),
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

    func resetPlayQueue(
        queueID: Int,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexPlayQueuePage {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath,
            appendingPathComponents: [String(queueID), "reset"]
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
        guard let endpointPath = watched ? endpoints.scrobblePath : endpoints.unscrobblePath else {
            throw PlexAPIError.missingLibraryTimelineFeature
        }
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "identifier", value: endpoints.providerIdentifier),
            URLQueryItem(name: "key", value: ratingKey),
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

    private func isValidPlayQueueIdentifier(_ identifier: String) -> Bool {
        guard let identifier = identifier.nilIfBlank else {
            return false
        }
        return identifier.utf8.allSatisfy { (48...57).contains($0) }
    }
}
