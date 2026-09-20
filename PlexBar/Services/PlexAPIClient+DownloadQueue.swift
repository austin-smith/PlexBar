import PlexClientKit
import PlexModels
import Foundation

extension PlexAPIClient {
    func fetchOrCreateDownloadQueue(
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexDownloadQueue {
        try await downloadQueue(
            pathComponents: [],
            method: "POST",
            using: configuration
        )
    }

    func fetchDownloadQueue(
        queueID: Int,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexDownloadQueue {
        guard queueID > 0 else {
            throw PlexAPIError.invalidDownloadQueue
        }
        return try await downloadQueue(
            pathComponents: [String(queueID)],
            method: "GET",
            using: configuration
        )
    }

    func addToDownloadQueue(
        keys: [String],
        queueID: Int,
        decision: PlexDownloadDecisionParameters,
        using configuration: PlexConnectionConfiguration
    ) async throws -> [PlexAddedDownloadQueueItem] {
        guard queueID > 0,
              !keys.isEmpty,
              keys.allSatisfy(Self.isValidDownloadMetadataKey),
              Self.isValid(decision: decision),
              let endpoint = downloadQueueURL(
                  pathComponents: [String(queueID), "add"],
                  using: configuration
              ),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidDownloadQueue
        }

        components.queryItems = [
            URLQueryItem(name: "keys", value: keys.joined(separator: ","))
        ] + downloadDecisionQueryItems(decision)
        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }

        var request = downloadQueueRequest(
            url: url,
            method: "POST",
            using: configuration
        )
        applyDownloadDecisionHeaders(decision, to: &request)
        let data = try await data(for: request)
        do {
            return try JSONDecoder()
                .decode(PlexAddedDownloadQueueItemsEnvelope.self, from: data)
                .mediaContainer.items
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func fetchDownloadQueueItems(
        queueID: Int,
        itemIDs: [Int]? = nil,
        using configuration: PlexConnectionConfiguration
    ) async throws -> [PlexDownloadQueueItem] {
        guard queueID > 0,
              itemIDs?.isEmpty != true,
              itemIDs?.allSatisfy({ $0 > 0 }) != false else {
            throw PlexAPIError.invalidDownloadQueue
        }
        var pathComponents = [String(queueID), "items"]
        if let itemIDs {
            pathComponents.append(itemIDs.map(String.init).joined(separator: ","))
        }
        guard let endpoint = downloadQueueURL(
            pathComponents: pathComponents,
            using: configuration
        ) else {
            throw PlexAPIError.invalidServerURL
        }

        let request = downloadQueueRequest(url: endpoint, using: configuration)
        let data = try await data(for: request)
        do {
            return try JSONDecoder()
                .decode(PlexDownloadQueueItemsEnvelope.self, from: data)
                .mediaContainer.items
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func deleteDownloadQueueItems(
        queueID: Int,
        itemIDs: [Int],
        using configuration: PlexConnectionConfiguration
    ) async throws {
        try await mutateDownloadQueueItems(
            queueID: queueID,
            itemIDs: itemIDs,
            suffix: [],
            method: "DELETE",
            using: configuration
        )
    }

    func restartDownloadQueueItems(
        queueID: Int,
        itemIDs: [Int],
        using configuration: PlexConnectionConfiguration
    ) async throws {
        try await mutateDownloadQueueItems(
            queueID: queueID,
            itemIDs: itemIDs,
            suffix: ["restart"],
            method: "POST",
            using: configuration
        )
    }

    func fetchDownloadQueueDecision(
        queueID: Int,
        itemID: Int,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexDownloadQueueDecision {
        (try await fetchDownloadQueueDecisionDocument(
            queueID: queueID,
            itemID: itemID,
            using: configuration
        )).decision
    }

    func fetchDownloadQueueDecisionDocument(
        queueID: Int,
        itemID: Int,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexDownloadQueueDecisionDocument {
        guard let endpoint = downloadQueueItemURL(
            queueID: queueID,
            itemID: itemID,
            suffix: "decision",
            using: configuration
        ) else {
            throw PlexAPIError.invalidDownloadQueue
        }
        let request = downloadQueueRequest(url: endpoint, using: configuration)
        let data = try await data(for: request)
        do {
            let decision = try JSONDecoder()
                .decode(PlexDownloadQueueDecisionEnvelope.self, from: data)
                .mediaContainer
            return PlexDownloadQueueDecisionDocument(decision: decision, data: data)
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func downloadQueueMediaRequest(
        queueID: Int,
        itemID: Int,
        using configuration: PlexConnectionConfiguration
    ) throws -> URLRequest {
        guard let endpoint = downloadQueueItemURL(
            queueID: queueID,
            itemID: itemID,
            suffix: "media",
            using: configuration
        ) else {
            throw PlexAPIError.invalidDownloadQueue
        }
        return downloadQueueRequest(
            url: endpoint,
            accept: nil,
            using: configuration
        )
    }

    private func downloadQueue(
        pathComponents: [String],
        method: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexDownloadQueue {
        guard let endpoint = downloadQueueURL(
            pathComponents: pathComponents,
            using: configuration
        ) else {
            throw PlexAPIError.invalidServerURL
        }
        let request = downloadQueueRequest(
            url: endpoint,
            method: method,
            using: configuration
        )
        let data = try await data(for: request)
        do {
            let queues = try JSONDecoder()
                .decode(PlexDownloadQueueEnvelope.self, from: data)
                .mediaContainer.queues
            guard queues.count == 1, let queue = queues.first else {
                throw PlexAPIError.invalidDownloadQueue
            }
            return queue
        } catch let error as PlexAPIError {
            throw error
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    private func mutateDownloadQueueItems(
        queueID: Int,
        itemIDs: [Int],
        suffix: [String],
        method: String,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        guard queueID > 0,
              !itemIDs.isEmpty,
              itemIDs.allSatisfy({ $0 > 0 }),
              let endpoint = downloadQueueURL(
                  pathComponents: [
                      String(queueID),
                      "items",
                      itemIDs.map(String.init).joined(separator: ","),
                  ] + suffix,
                  using: configuration
              ) else {
            throw PlexAPIError.invalidDownloadQueue
        }
        let request = downloadQueueRequest(
            url: endpoint,
            method: method,
            using: configuration
        )
        _ = try await responseData(for: request)
    }

    private func downloadQueueItemURL(
        queueID: Int,
        itemID: Int,
        suffix: String,
        using configuration: PlexConnectionConfiguration
    ) -> URL? {
        guard queueID > 0, itemID > 0 else {
            return nil
        }
        return downloadQueueURL(
            pathComponents: [String(queueID), "item", String(itemID), suffix],
            using: configuration
        )
    }

    private func downloadQueueURL(
        pathComponents: [String],
        using configuration: PlexConnectionConfiguration
    ) -> URL? {
        guard !pathComponents.isEmpty else {
            return PlexURLBuilder.endpointURL(
                serverURL: configuration.serverURL,
                path: "/downloadQueue"
            )
        }
        return PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: "/downloadQueue",
            appendingPathComponents: pathComponents
        )
    }

    private func downloadQueueRequest(
        url: URL,
        method: String = "GET",
        accept: String? = "application/json",
        using configuration: PlexConnectionConfiguration
    ) -> URLRequest {
        PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            method: method,
            accept: accept,
            token: configuration.token
        )
    }

    private func downloadDecisionQueryItems(
        _ decision: PlexDownloadDecisionParameters
    ) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        items.appendIfPresent(name: "path", value: decision.mediaPath)
        items.appendIfPresent(name: "mediaIndex", value: decision.mediaIndex)
        items.appendIfPresent(name: "partIndex", value: decision.partIndex)
        items.appendIfPresent(name: "protocol", value: decision.deliveryProtocol?.rawValue)
        items.appendIfPresent(name: "directPlay", value: decision.allowsDirectPlay)
        items.appendIfPresent(name: "directStream", value: decision.allowsDirectStream)
        items.appendIfPresent(name: "directStreamAudio", value: decision.allowsDirectStreamAudio)
        items.appendIfPresent(name: "subtitles", value: decision.subtitleMode?.rawValue)
        items.appendIfPresent(name: "advancedSubtitles", value: decision.advancedSubtitleMode?.rawValue)
        items.appendIfPresent(name: "videoBitrate", value: decision.videoBitrate)
        items.appendIfPresent(name: "videoQuality", value: decision.videoQuality)
        items.appendIfPresent(name: "videoResolution", value: decision.videoResolution)
        items.appendIfPresent(name: "musicBitrate", value: decision.musicBitrate)
        return items
    }

    private func applyDownloadDecisionHeaders(
        _ decision: PlexDownloadDecisionParameters,
        to request: inout URLRequest
    ) {
        request.setValue(
            decision.sessionIdentifier?.nilIfBlank,
            forHTTPHeaderField: "X-Plex-Session-Identifier"
        )
        request.setValue(
            decision.clientProfileName?.nilIfBlank,
            forHTTPHeaderField: "X-Plex-Client-Profile-Name"
        )
        request.setValue(
            decision.clientProfileExtra?.nilIfBlank,
            forHTTPHeaderField: "X-Plex-Client-Profile-Extra"
        )
    }

    private static func isValidDownloadMetadataKey(_ key: String) -> Bool {
        guard let key = key.nilIfBlank,
              key.hasPrefix("/library/metadata/") else {
            return false
        }
        return URL(string: key)?.scheme == nil && URL(string: key)?.host == nil
    }

    private static func isValid(decision: PlexDownloadDecisionParameters) -> Bool {
        if let path = decision.mediaPath,
           !isValidDownloadMetadataKey(path) {
            return false
        }
        if let mediaIndex = decision.mediaIndex, mediaIndex < -1 {
            return false
        }
        if let partIndex = decision.partIndex, partIndex < -1 {
            return false
        }
        let nonnegativeValues = [
            decision.videoBitrate,
            decision.musicBitrate,
        ].compactMap { $0 }
        guard nonnegativeValues.allSatisfy({ $0 >= 0 }) else {
            return false
        }
        if let videoQuality = decision.videoQuality,
           !(0...99).contains(videoQuality) {
            return false
        }
        if let resolution = decision.videoResolution,
           !isValidDownloadResolution(resolution) {
            return false
        }
        return true
    }

    private static func isValidDownloadResolution(_ value: String) -> Bool {
        let components = value.split(whereSeparator: { $0 == "x" || $0 == ":" })
        guard components.count == 2,
              let width = Int(components[0]), width > 0,
              let height = Int(components[1]), height > 0 else {
            return false
        }
        return true
    }
}

private extension Array where Element == URLQueryItem {
    mutating func appendIfPresent(name: String, value: String?) {
        guard let value = value?.nilIfBlank else { return }
        append(URLQueryItem(name: name, value: value))
    }

    mutating func appendIfPresent(name: String, value: Int?) {
        guard let value else { return }
        append(URLQueryItem(name: name, value: String(value)))
    }

    mutating func appendIfPresent(name: String, value: Bool?) {
        guard let value else { return }
        append(URLQueryItem(name: name, value: value ? "1" : "0"))
    }
}
