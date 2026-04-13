import Foundation

struct PlexAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLibraries(using configuration: PlexConnectionConfiguration) async throws -> [PlexLibrary] {
        let sections = try await fetchLibrarySections(using: configuration)

        return try await withThrowingTaskGroup(of: PlexLibrary.self) { group in
            for section in sections where section.isBrowsableLibrary {
                group.addTask {
                    try await fetchLibrarySummary(for: section, using: configuration)
                }
            }

            var libraries: [PlexLibrary] = []
            for try await library in group {
                libraries.append(library)
            }

            return libraries.sorted { lhs, rhs in
                if lhs.sortDate != rhs.sortDate {
                    return lhs.sortDate > rhs.sortDate
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
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

    func fetchMetadataItems(
        using configuration: PlexConnectionConfiguration,
        ids: [String],
        chunkSize: Int = 50
    ) async throws -> [PlexMetadataItem] {
        guard !ids.isEmpty else {
            return []
        }

        var items: [PlexMetadataItem] = []

        for chunk in ids.chunked(into: chunkSize) {
            guard let endpoint = PlexURLBuilder.endpointURL(
                serverURL: configuration.serverURL,
                path: "/library/metadata/\(chunk.joined(separator: ","))"
            ) else {
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
                let decodedResponse = try JSONDecoder().decode(PlexMetadataEnvelope.self, from: data)
                items.append(contentsOf: decodedResponse.mediaContainer.metadata ?? [])
            } catch {
                throw PlexAPIError.decodingFailed(error)
            }
        }

        return items
    }

    func fetchHistorySeriesIdentities(
        using configuration: PlexConnectionConfiguration,
        episodeIDs: [String]
    ) async throws -> [String: PlexHistorySeriesIdentity] {
        guard !episodeIDs.isEmpty else {
            return [:]
        }

        let requestedEpisodeIDs = Set(episodeIDs)
        let metadataItems = try await fetchMetadataItems(
            using: configuration,
            ids: Array(requestedEpisodeIDs).sorted()
        )

        let resolvedIdentities = Dictionary(uniqueKeysWithValues: metadataItems.compactMap(\.historySeriesResolution))
        let unresolvedEpisodeIDs = requestedEpisodeIDs.subtracting(resolvedIdentities.keys)

        guard unresolvedEpisodeIDs.isEmpty else {
            throw PlexAPIError.missingHistorySeriesIdentity(Array(unresolvedEpisodeIDs).sorted())
        }

        return resolvedIdentities
    }

    private func fetchLibrarySections(using configuration: PlexConnectionConfiguration) async throws -> [PlexLibrarySection] {
        guard let endpoint = PlexURLBuilder.endpointURL(serverURL: configuration.serverURL, path: "/library/sections/all") else {
            throw PlexAPIError.invalidServerURL
        }

        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: endpoint,
            accept: "application/json",
            token: configuration.token
        )

        let data = try await data(for: request)

        do {
            let decodedResponse = try JSONDecoder().decode(PlexLibrarySectionsEnvelope.self, from: data)
            return decodedResponse.mediaContainer.directory ?? []
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    private func fetchLibrarySummary(
        for section: PlexLibrarySection,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexLibrary {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: "/library/sections/\(section.key)/all"
        ),
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }

        components.queryItems = [
            URLQueryItem(name: "sort", value: "addedAt:desc")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }

        async let primarySummaryTask = fetchLibraryPrimarySummary(
            from: url,
            using: configuration
        )

        let secondarySummaryTask: Task<(count: Int, label: String)?, Never>? = if let secondarySummary = PlexLibraryType(rawValue: section.type).preferredSecondarySummary {
            Task {
                do {
                    let count = try await fetchLibraryCount(
                        sectionID: section.key,
                        type: secondarySummary.queryType,
                        using: configuration
                    )
                    return (count, secondarySummary.label)
                } catch {
                    return nil
                }
            }
        } else {
            nil
        }

        let primarySummary = try await primarySummaryTask
        let secondarySummary = await secondarySummaryTask?.value

        return section.librarySummary(
            itemCount: primarySummary.itemCount,
            recentItem: primarySummary.recentItem,
            secondaryCount: secondarySummary?.count,
            secondaryCountLabel: secondarySummary?.label
        )
    }

    private func fetchLibraryPrimarySummary(
        from url: URL,
        using configuration: PlexConnectionConfiguration
    ) async throws -> (itemCount: Int, recentItem: PlexLibraryRecentItem?) {
        var request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            accept: "application/json",
            token: configuration.token
        )
        request.setValue("0", forHTTPHeaderField: "X-Plex-Container-Start")
        request.setValue("1", forHTTPHeaderField: "X-Plex-Container-Size")

        let (data, response) = try await responseData(for: request)

        do {
            let decodedResponse = try JSONDecoder().decode(PlexLibraryItemsEnvelope.self, from: data)
            let recentItem = decodedResponse.mediaContainer.metadata?.first
            let totalSize = totalSize(from: response) ?? decodedResponse.mediaContainer.totalSize ?? decodedResponse.mediaContainer.size ?? 0
            return (totalSize, recentItem)
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    private func fetchLibraryCount(
        sectionID: String,
        type: Int,
        using configuration: PlexConnectionConfiguration
    ) async throws -> Int {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: "/library/sections/\(sectionID)/all"
        ),
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }

        components.queryItems = [
            URLQueryItem(name: "type", value: String(type))
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }

        var request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            accept: "application/json",
            token: configuration.token
        )
        request.setValue("0", forHTTPHeaderField: "X-Plex-Container-Start")
        request.setValue("0", forHTTPHeaderField: "X-Plex-Container-Size")

        let (_, response) = try await responseData(for: request)
        return totalSize(from: response) ?? 0
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, _) = try await responseData(for: request)
        return data
    }

    private func responseData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlexAPIError.badStatusCode(httpResponse.statusCode)
        }

        return (data, httpResponse)
    }

    private func totalSize(from response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: "X-Plex-Container-Total-Size") else {
            return nil
        }

        return Int(value)
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
    case missingHistorySeriesIdentity([String])

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
        case .missingHistorySeriesIdentity:
            return "Plex did not return enough metadata to build watch history charts."
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

private struct PlexLibrarySectionsEnvelope: Decodable {
    let mediaContainer: PlexLibrarySectionsContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

private struct PlexLibrarySectionsContainer: Decodable {
    let directory: [PlexLibrarySection]?

    enum CodingKeys: String, CodingKey {
        case directory = "Directory"
    }
}

private struct PlexLibrarySection: Decodable {
    let key: String
    let title: String
    let type: String
    let composite: String?
    let art: String?
    let thumb: String?
    let updatedAt: Int?
    let scannedAt: Int?
    let contentChangedAt: Int?
    let hidden: Bool?
    let content: Bool?
    let directory: Bool?

    enum CodingKeys: String, CodingKey {
        case key
        case title
        case type
        case composite
        case art
        case thumb
        case updatedAt
        case scannedAt
        case contentChangedAt
        case hidden
        case content
        case directory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(String.self, forKey: .type)
        composite = try container.decodeIfPresent(String.self, forKey: .composite)
        art = try container.decodeIfPresent(String.self, forKey: .art)
        thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
        updatedAt = try container.decodeIfPresent(Int.self, forKey: .updatedAt)
        scannedAt = try container.decodeIfPresent(Int.self, forKey: .scannedAt)
        contentChangedAt = try container.decodeIfPresent(Int.self, forKey: .contentChangedAt)
        hidden = try container.decodeFlexibleBoolIfPresent(forKey: .hidden)
        content = try container.decodeFlexibleBoolIfPresent(forKey: .content)
        directory = try container.decodeFlexibleBoolIfPresent(forKey: .directory)
    }

    var isBrowsableLibrary: Bool {
        hidden != true && content != false && directory != false
    }

    func librarySummary(
        itemCount: Int,
        recentItem: PlexLibraryRecentItem?,
        secondaryCount: Int?,
        secondaryCountLabel: String?
    ) -> PlexLibrary {
        PlexLibrary(
            id: key,
            title: title,
            type: PlexLibraryType(rawValue: type),
            compositePath: composite?.nilIfBlank,
            artPath: recentItem?.art?.nilIfBlank ?? art?.nilIfBlank,
            thumbPath: recentItem?.thumb?.nilIfBlank ?? thumb?.nilIfBlank,
            itemCount: itemCount,
            secondaryCount: secondaryCount,
            secondaryCountLabel: secondaryCountLabel,
            updatedAt: updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            scannedAt: scannedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            contentChangedAt: contentChangedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            latestAddedAt: recentItem?.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            latestItemTitle: recentItem?.title?.nilIfBlank
        )
    }
}

private struct PlexLibraryItemsEnvelope: Decodable {
    let mediaContainer: PlexLibraryItemsContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

private struct PlexLibraryItemsContainer: Decodable {
    let size: Int?
    let totalSize: Int?
    let metadata: [PlexLibraryRecentItem]?

    enum CodingKeys: String, CodingKey {
        case size
        case totalSize
        case metadata = "Metadata"
    }
}

private struct PlexLibraryRecentItem: Decodable {
    let title: String?
    let addedAt: Int?
    let art: String?
    let thumb: String?
}

private extension KeyedDecodingContainer {
    func decodeFlexibleBoolIfPresent(forKey key: Key) throws -> Bool? {
        if contains(key) == false {
            return nil
        }

        if try decodeNil(forKey: key) {
            return nil
        }

        if let boolValue = try? decode(Bool.self, forKey: key) {
            return boolValue
        }

        if let intValue = try? decode(Int.self, forKey: key) {
            return intValue != 0
        }

        if let stringValue = try? decode(String.self, forKey: key) {
            switch stringValue.lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return nil
            }
        }

        return nil
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

struct PlexMetadataItem: Decodable, Equatable {
    let ratingKey: String
    let grandparentRatingKey: String?
    let grandparentTitle: String?
    let grandparentThumb: String?

    enum CodingKeys: String, CodingKey {
        case ratingKey
        case grandparentRatingKey
        case grandparentTitle
        case grandparentThumb
    }

    var historySeriesResolution: (String, PlexHistorySeriesIdentity)? {
        guard let episodeID = ratingKey.nilIfBlank,
              let seriesID = grandparentRatingKey?.nilIfBlank,
              let seriesTitle = grandparentTitle?.nilIfBlank else {
            return nil
        }

        return (
            episodeID,
            PlexHistorySeriesIdentity(
                id: seriesID,
                title: seriesTitle,
                posterPath: grandparentThumb?.nilIfBlank
            )
        )
    }
}

private struct PlexMetadataEnvelope: Decodable {
    let mediaContainer: PlexMetadataContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

private struct PlexMetadataContainer: Decodable {
    let metadata: [PlexMetadataItem]?

    enum CodingKeys: String, CodingKey {
        case metadata = "Metadata"
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }

        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)

        var startIndex = 0
        while startIndex < count {
            let endIndex = Swift.min(startIndex + size, count)
            chunks.append(Array(self[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return chunks
    }
}
