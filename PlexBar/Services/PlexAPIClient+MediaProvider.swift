import PlexClientKit
import Foundation

extension PlexAPIClient {
    func fetchLibraryProviderEndpoints(
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexLibraryProviderEndpoints {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: "/media/providers"
        ) else {
            throw PlexAPIError.invalidServerURL
        }

        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: endpoint,
            accept: "application/json",
            token: configuration.token
        )
        let responseData = try await data(for: request)

        do {
            let envelope = try JSONDecoder().decode(PlexMediaProvidersEnvelope.self, from: responseData)
            return try envelope.mediaContainer.libraryProviderEndpoints()
        } catch let error as PlexAPIError {
            throw error
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func setPersonalRating(
        _ rating: Double?,
        ratingKey: String,
        endpoints: PlexLibraryProviderEndpoints,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        let encodedRating = rating ?? 0
        guard encodedRating.isFinite,
              (rating == nil || (1...10).contains(encodedRating)) else {
            throw PlexAPIError.invalidPersonalRating
        }
        guard let ratePath = endpoints.ratePath else {
            throw PlexAPIError.missingLibraryRateFeature
        }
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: ratePath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "identifier", value: endpoints.providerIdentifier),
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "rating", value: String(encodedRating)),
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

    func refreshMediaMetadata(
        ratingKey: String,
        endpoints: PlexLibraryProviderEndpoints,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        guard endpoints.canManage,
              let metadataPath = endpoints.metadataPath else {
            throw PlexAPIError.libraryManagementUnavailable
        }
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: metadataPath,
            appendingPathComponents: [ratingKey, "refresh"]
        ) else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: endpoint,
            method: "PUT",
            accept: "application/json",
            token: configuration.token
        )
        _ = try await responseData(for: request)
    }

    func removeFromContinueWatching(
        ratingKey: String,
        endpoints: PlexLibraryProviderEndpoints,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        guard let actionPath = endpoints.removeFromContinueWatchingPath else {
            throw PlexAPIError.missingRemoveFromContinueWatchingAction
        }
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: actionPath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "ratingKey", value: ratingKey),
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
}
