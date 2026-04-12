import Foundation

struct PlexAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSessions(using configuration: PlexConnectionConfiguration) async throws -> [PlexSession] {
        guard let endpoint = PlexURLBuilder.endpointURL(serverURL: configuration.serverURL, path: "/status/sessions") else {
            throw PlexAPIError.invalidServerURL
        }

        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: endpoint,
            accept: "application/json",
            token: configuration.token
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlexAPIError.badStatusCode(httpResponse.statusCode)
        }

        do {
            let decodedResponse = try JSONDecoder().decode(PlexSessionsEnvelope.self, from: data)
            return decodedResponse.mediaContainer.metadata ?? []
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }
}

struct PlexConnectionConfiguration {
    let serverURL: URL
    let token: String
    let clientContext: PlexClientContext
}

enum PlexAPIError: LocalizedError {
    case invalidServerURL
    case missingToken
    case invalidResponse
    case badStatusCode(Int)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid Plex server URL, for example http://192.168.1.10:32400."
        case .missingToken:
            return "Add a Plex token before refreshing sessions."
        case .invalidResponse:
            return "Plex returned a response that PlexBar could not read."
        case .badStatusCode(let statusCode):
            return "Plex returned HTTP \(statusCode). Check the server URL and token."
        case .decodingFailed:
            return "Plex returned session data in an unexpected format."
        }
    }
}

private struct PlexSessionsEnvelope: Decodable {
    let mediaContainer: PlexSessionsContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

private struct PlexSessionsContainer: Decodable {
    let metadata: [PlexSession]?

    enum CodingKeys: String, CodingKey {
        case metadata = "Metadata"
    }
}
