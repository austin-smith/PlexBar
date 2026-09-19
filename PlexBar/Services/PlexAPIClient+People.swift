import PlexClientKit
import PlexModels
import Foundation

extension PlexAPIClient {
    func fetchEpisodeSeriesCast(
        for item: PlexMediaItem,
        using configuration: PlexConnectionConfiguration
    ) async throws -> [PlexTag] {
        guard let seriesRatingKey = item.episodeSeriesCastRatingKey else {
            return []
        }

        let series = try await fetchMediaMetadata(
            ratingKey: seriesRatingKey,
            using: configuration
        )
        guard series.ratingKey == seriesRatingKey,
              series.type?.caseInsensitiveCompare("show") == .orderedSame else {
            throw PlexAPIError.invalidResponse
        }
        return series.roles
    }

    func fetchPerson(
        identifier: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexTag {
        let endpoint = try personEndpoint(
            identifier: identifier,
            suffix: nil,
            configuration: configuration
        )
        let responseData = try await data(
            for: peopleRequest(url: endpoint, configuration: configuration)
        )

        do {
            let decoded = try JSONDecoder().decode(PlexPeopleEnvelope.self, from: responseData)
            guard let person = decoded.mediaContainer.people.first else {
                throw PlexAPIError.invalidResponse
            }
            return person
        } catch let error as PlexAPIError {
            throw error
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func fetchPersonMedia(
        identifier: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> [PlexMediaItem] {
        let endpoint = try personEndpoint(
            identifier: identifier,
            suffix: "media",
            configuration: configuration
        )
        let responseData = try await data(
            for: peopleRequest(url: endpoint, configuration: configuration)
        )

        do {
            return try JSONDecoder()
                .decode(PlexMediaEnvelope.self, from: responseData)
                .mediaContainer
                .metadata
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }
}

private extension PlexAPIClient {
    func peopleRequest(
        url: URL,
        configuration: PlexConnectionConfiguration
    ) -> URLRequest {
        PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            accept: "application/json",
            token: configuration.token
        )
    }

    func personEndpoint(
        identifier: String,
        suffix: String?,
        configuration: PlexConnectionConfiguration
    ) throws -> URL {
        var components = [identifier]
        if let suffix {
            components.append(suffix)
        }
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: "/library/people",
            appendingPathComponents: components
        ) else {
            throw PlexAPIError.invalidServerURL
        }
        return endpoint
    }
}
