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

    func fetchHistory(
        using configuration: PlexConnectionConfiguration,
        since: Date,
        pageSize: Int = 200
    ) async throws -> [PlexHistoryItem] {
        guard let endpoint = PlexURLBuilder.endpointURL(serverURL: configuration.serverURL, path: "/status/sessions/history/all"),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }

        let cutoffTimestamp = String(Int(since.timeIntervalSince1970))
        var offset = 0
        var allItems: [PlexHistoryItem] = []
        var totalSize: Int?

        while true {
            components.queryItems = [
                URLQueryItem(name: "sort", value: "viewedAt:desc"),
                URLQueryItem(name: "viewedAt>", value: cutoffTimestamp)
            ]

            guard let historyURL = components.url else {
                throw PlexAPIError.invalidServerURL
            }

            var request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
                url: historyURL,
                accept: "application/json",
                token: configuration.token
            )
            request.setValue(String(offset), forHTTPHeaderField: "X-Plex-Container-Start")
            request.setValue(String(pageSize), forHTTPHeaderField: "X-Plex-Container-Size")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PlexAPIError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw PlexAPIError.badStatusCode(httpResponse.statusCode)
            }

            do {
                let decodedResponse = try JSONDecoder().decode(PlexHistoryEnvelope.self, from: data)
                let pageItems = decodedResponse.mediaContainer.metadata ?? []
                allItems.append(contentsOf: pageItems)

                if totalSize == nil,
                   let totalSizeHeader = httpResponse.value(forHTTPHeaderField: "X-Plex-Container-Total-Size"),
                   let parsedTotalSize = Int(totalSizeHeader) {
                    totalSize = parsedTotalSize
                }

                if pageItems.count < pageSize {
                    break
                }

                offset += pageItems.count

                if let totalSize, offset >= totalSize {
                    break
                }
            } catch {
                throw PlexAPIError.decodingFailed(error)
            }
        }

        return allItems
    }

    func fetchAccounts(using configuration: PlexConnectionConfiguration) async throws -> [PlexAccount] {
        guard let endpoint = PlexURLBuilder.endpointURL(serverURL: configuration.serverURL, path: "/statistics/media") else {
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
            let decodedResponse = try JSONDecoder().decode(PlexStatisticsEnvelope.self, from: data)
            return decodedResponse.mediaContainer.accounts ?? []
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
            return "Plex returned data in an unexpected format."
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

private struct PlexHistoryEnvelope: Decodable {
    let mediaContainer: PlexHistoryContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

private struct PlexHistoryContainer: Decodable {
    let metadata: [PlexHistoryItem]?

    enum CodingKeys: String, CodingKey {
        case metadata = "Metadata"
    }
}

private struct PlexStatisticsEnvelope: Decodable {
    let mediaContainer: PlexStatisticsContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

private struct PlexStatisticsContainer: Decodable {
    let accounts: [PlexAccount]?

    enum CodingKeys: String, CodingKey {
        case accounts = "Account"
    }
}
