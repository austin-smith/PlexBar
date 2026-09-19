import PlexClientKit
import PlexModels
import Foundation
import OSLog

private let plexMediaAPILogger = Logger(
    subsystem: "com.crapshack.PlexBar",
    category: "PlexAPIClient.Media"
)

extension PlexAPIClient {
    func fetchMediaPage(
        libraryID: String,
        using configuration: PlexConnectionConfiguration,
        start: Int = 0,
        size: Int = 100,
        searchQuery: String? = nil,
        browseOptions: PlexLibraryBrowseOptions = .default
    ) async throws -> PlexMediaPage {
        try await fetchMediaPage(
            contentPath: "/library/sections/\(libraryID)/all",
            using: configuration,
            start: start,
            size: size,
            searchQuery: searchQuery,
            browseOptions: browseOptions
        )
    }

    func fetchMediaPage(
        contentPath: String,
        using configuration: PlexConnectionConfiguration,
        start: Int = 0,
        size: Int = 100,
        searchQuery: String? = nil,
        browseOptions: PlexLibraryBrowseOptions = .default
    ) async throws -> PlexMediaPage {
        let safeStart = max(start, 0)
        guard let url = mediaPageURL(
            contentPath: contentPath,
            configuration: configuration,
            searchQuery: searchQuery,
            browseOptions: browseOptions
        ) else {
            throw PlexAPIError.invalidServerURL
        }

        return try await fetchMediaPage(
            url: url,
            configuration: configuration,
            start: safeStart,
            size: size
        )
    }

    func fetchMediaChildren(
        of item: PlexMediaItem,
        using configuration: PlexConnectionConfiguration,
        start: Int = 0,
        size: Int = 100
    ) async throws -> PlexMediaPage {
        guard let path = item.childrenPath,
              let url = PlexURLBuilder.endpointURL(
                  serverURL: configuration.serverURL,
                  path: path
              ) else {
            throw PlexAPIError.invalidResponse
        }

        return try await fetchMediaPage(
            url: url,
            configuration: configuration,
            start: max(start, 0),
            size: size
        )
    }

    private func fetchMediaPage(
        url: URL,
        configuration: PlexConnectionConfiguration,
        start: Int,
        size: Int
    ) async throws -> PlexMediaPage {

        var request = authenticatedRequest(url: url, configuration: configuration)
        request.setValue(String(start), forHTTPHeaderField: "X-Plex-Container-Start")
        request.setValue(String(max(size, 1)), forHTTPHeaderField: "X-Plex-Container-Size")
        let (data, response) = try await responseData(for: request)

        do {
            let decoded = try JSONDecoder().decode(PlexMediaEnvelope.self, from: data)
            return PlexMediaPage(
                items: decoded.mediaContainer.metadata,
                offset: decoded.mediaContainer.offset ?? start,
                totalSize: totalSize(from: response) ?? decoded.mediaContainer.totalSize
            )
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func fetchMediaMetadata(
        ratingKey: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexMediaItem {
        try await fetchMediaMetadata(
            path: "/library/metadata/\(ratingKey)?includeOptionalElements=Chapter,Image,Marker,Rating&includeGuids=1",
            using: configuration
        )
    }

    func fetchMediaMetadata(
        path: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexMediaItem {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: path
        ) else {
            throw PlexAPIError.invalidServerURL
        }

        let responseData = try await data(for: authenticatedRequest(url: endpoint, configuration: configuration))
        do {
            let decoded = try JSONDecoder().decode(PlexMediaEnvelope.self, from: responseData)
            guard let item = decoded.mediaContainer.metadata.first else {
                throw PlexAPIError.invalidResponse
            }
            return item
        } catch let error as PlexAPIError {
            throw error
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func fetchHomeHubs(
        endpoints: PlexLibraryProviderEndpoints,
        using configuration: PlexConnectionConfiguration,
        count: Int = 20
    ) async throws -> [PlexHub] {
        guard let promotedPath = endpoints.promotedPath else {
            throw PlexAPIError.missingLibraryPromotedFeature
        }
        guard let continueWatchingPath = endpoints.continueWatchingPath else {
            throw PlexAPIError.missingLibraryContinueWatchingFeature
        }
        async let promoted = fetchHubs(endpointPath: promotedPath, using: configuration, count: count)
        async let continuation = fetchHubs(endpointPath: continueWatchingPath, using: configuration, count: count)
        return try await PlexHub.homeHubs(promoted: promoted, continueWatching: continuation)
    }

    func fetchHubs(
        endpointPath: String,
        using configuration: PlexConnectionConfiguration,
        count: Int = 20
    ) async throws -> [PlexHub] {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "count" }
        queryItems.append(URLQueryItem(name: "count", value: String(max(count, 1))))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }

        let responseData = try await data(for: authenticatedRequest(url: url, configuration: configuration))
        do {
            let decoded = try JSONDecoder().decode(PlexHubEnvelope.self, from: responseData)
            return decoded.mediaContainer.hubs
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func fetchSearchHubs(
        query: String,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration,
        limit: Int = 12
    ) async throws -> [PlexHub] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return []
        }
        guard let endpoint = PlexURLBuilder.endpointURL(
                  serverURL: configuration.serverURL,
                  path: endpointPath
              ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "query" || $0.name == "limit" }
        queryItems += [
            URLQueryItem(name: "query", value: normalizedQuery),
            URLQueryItem(name: "limit", value: String(max(limit, 1))),
        ]
        components.queryItems = queryItems

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }

        let responseData = try await data(
            for: authenticatedRequest(url: url, configuration: configuration)
        )
        do {
            let decoded = try JSONDecoder().decode(PlexHubEnvelope.self, from: responseData)
            return decoded.mediaContainer.hubs.filter { !$0.metadata.isEmpty }
        } catch {
            plexMediaAPILogger.error(
                "Global search response decoding failed: \(String(describing: error), privacy: .public)"
            )
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func fetchRelatedHubs(
        ratingKey: String,
        using configuration: PlexConnectionConfiguration,
        count: Int = 12
    ) async throws -> [PlexHub] {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: "/hubs/metadata/\(ratingKey)/related"
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = [URLQueryItem(name: "count", value: String(max(count, 1)))]

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }

        let responseData = try await data(
            for: authenticatedRequest(url: url, configuration: configuration)
        )
        do {
            let decoded = try JSONDecoder().decode(PlexHubEnvelope.self, from: responseData)
            return decoded.mediaContainer.hubs.filter { !$0.metadata.isEmpty }
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func fetchPostPlayHubs(
        ratingKey: String,
        using configuration: PlexConnectionConfiguration,
        count: Int = 12
    ) async throws -> [PlexHub] {
        guard Int(ratingKey) != nil,
              let endpoint = PlexURLBuilder.endpointURL(
                  serverURL: configuration.serverURL,
                  path: "/hubs/metadata",
                  appendingPathComponents: [ratingKey, "postplay"]
              ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = [URLQueryItem(name: "count", value: String(max(count, 1)))]

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }

        let responseData = try await data(
            for: authenticatedRequest(url: url, configuration: configuration)
        )
        do {
            let decoded = try JSONDecoder().decode(PlexHubEnvelope.self, from: responseData)
            return decoded.mediaContainer.hubs.filter { !$0.metadata.isEmpty }
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func fetchMediaExtras(
        ratingKey: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> [PlexMediaItem] {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: "/library/metadata/\(ratingKey)/extras"
        ) else {
            throw PlexAPIError.invalidServerURL
        }

        let responseData = try await data(
            for: authenticatedRequest(url: endpoint, configuration: configuration)
        )
        do {
            let decoded = try JSONDecoder().decode(PlexMediaEnvelope.self, from: responseData)
            return decoded.mediaContainer.metadata
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func makePlaybackPlan(
        for item: PlexMediaItem,
        using configuration: PlexConnectionConfiguration,
        capabilities: PlexPlaybackCapabilities,
        source requestedSource: PlexPlaybackSource? = nil,
        videoQuality: PlexVideoQuality = .original,
        musicQuality: PlexMusicQuality = .original,
        audioBoost: PlexAudioBoost = .none,
        streamingPolicy: PlexPlaybackStreamingPolicy = .automatic,
        subtitleBurnMode: PlexSubtitleBurnMode = .automatic,
        subtitleSize: PlexSubtitleSize = .normal,
        automaticallySyncSubtitles: Bool = true,
        automaticallyAdjustVideoQuality: Bool = false,
        playSmallerVideosAtOriginalQuality: Bool = true,
        forceVideoTranscode: Bool = false,
        startTimeOverride: TimeInterval? = nil,
        forceServerMediaSelection: Bool = false
    ) async throws -> PlexPlaybackPlan {
        let source: PlexPlaybackSource
        if let requestedSource {
            guard item.playbackSource(mediaIndex: requestedSource.mediaIndex) == requestedSource else {
                throw PlexAPIError.noPlayableMedia
            }
            source = requestedSource
        } else if let defaultPlaybackSource = item.defaultPlaybackSource {
            source = defaultPlaybackSource
        } else {
            throw PlexAPIError.noPlayableMedia
        }

        let sessionIdentifier = UUID().uuidString.lowercased()
        let startTime = max(
            startTimeOverride ?? TimeInterval(item.viewOffset ?? 0) / 1_000,
            0
        )
        let requestParameters = PlexPlaybackRequestParameters(
            item: item,
            source: source,
            videoQuality: videoQuality,
            musicQuality: musicQuality,
            audioBoost: audioBoost,
            streamingPolicy: streamingPolicy,
            subtitleBurnMode: subtitleBurnMode,
            subtitleSize: subtitleSize,
            automaticallySyncSubtitles: automaticallySyncSubtitles,
            automaticallyAdjustVideoQuality: automaticallyAdjustVideoQuality,
            playSmallerVideosAtOriginalQuality: playSmallerVideosAtOriginalQuality,
            forceVideoTranscode: forceVideoTranscode,
            sessionIdentifier: sessionIdentifier,
            startTime: startTime,
            forceServerMediaSelection: forceServerMediaSelection
        )
        let mediaKind = PlexPlaybackMediaKind(media: item.media[source.mediaIndex])

        if streamingPolicy.forceDirectPlay,
           requestParameters.permitsDirectPlay,
           let path = capabilities.directPlayPath(for: item, source: source),
           let playbackURL = authenticatedMediaURL(
               configuration: configuration,
               path: path,
               sessionIdentifier: sessionIdentifier,
               queryItems: []
           ) {
            return PlexPlaybackPlan(
                url: playbackURL,
                method: .directPlay,
                mediaKind: mediaKind,
                sessionIdentifier: sessionIdentifier,
                ratingKey: item.ratingKey,
                duration: item.duration.map { TimeInterval($0) / 1_000 },
                startTime: startTime,
                source: source,
                usesServerMediaSelection: false
            )
        }

        let queryItems = requestParameters.queryItems
        let decision = try await playbackDecision(
            configuration: configuration,
            capabilities: capabilities,
            mediaKind: mediaKind,
            sessionIdentifier: sessionIdentifier,
            queryItems: queryItems
        )
        let selection = try playbackSelection(from: decision, mediaKind: mediaKind)
        let playbackURL = try playbackURL(
            selection: selection,
            configuration: configuration,
            capabilities: capabilities,
            mediaKind: mediaKind,
            sessionIdentifier: sessionIdentifier,
            queryItems: queryItems
        )

        return PlexPlaybackPlan(
            url: playbackURL,
            method: selection.method,
            mediaKind: mediaKind,
            sessionIdentifier: sessionIdentifier,
            ratingKey: item.ratingKey,
            duration: item.duration.map { TimeInterval($0) / 1_000 },
            startTime: startTime,
            source: source,
            usesServerMediaSelection: forceServerMediaSelection,
            supportsAudioBoost: selection.supportsAudioBoost
                && requestParameters.hasMultichannelAudioSource,
            supportsSubtitleAutoSync: requestParameters.supportsSubtitleAutoSync
        )
    }

    func selectMediaStreams(
        partID: Int,
        audioStreamID: Int? = nil,
        subtitleStreamID: Int? = nil,
        allParts: Bool = true,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        let parameters = PlexMediaSelectionRequestParameters(
            partID: partID,
            audioStreamID: audioStreamID,
            subtitleStreamID: subtitleStreamID,
            allParts: allParts
        )
        guard parameters.hasSelection else {
            throw PlexAPIError.invalidResponse
        }
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: parameters.path
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = parameters.queryItems

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }
        var request = authenticatedRequest(url: url, configuration: configuration)
        request.httpMethod = "PUT"
        _ = try await responseData(for: request)
    }

    func reportTimeline(
        _ update: PlexTimelineUpdate,
        endpointPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexTimelineResponse {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: endpointPath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = (components.queryItems ?? [])
            + PlexTimelineRequestParameters(update: update).queryItems

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }

        var request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            method: "POST",
            accept: "application/json",
            token: configuration.token
        )
        request.setValue(update.sessionIdentifier, forHTTPHeaderField: "X-Plex-Session-Identifier")
        let responseData = try await data(for: request)
        do {
            return try JSONDecoder()
                .decode(PlexTimelineResponseEnvelope.self, from: responseData)
                .mediaContainer
                .response
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    private func mediaPageURL(
        contentPath: String,
        configuration: PlexConnectionConfiguration,
        searchQuery: String?,
        browseOptions: PlexLibraryBrowseOptions
    ) -> URL? {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: contentPath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var queryItems = components.queryItems ?? []
        for queryItem in browseOptions.queryItems {
            queryItems.removeAll { $0.name == queryItem.name }
            queryItems.append(queryItem)
        }
        if let searchQuery = searchQuery?.nilIfBlank {
            queryItems.removeAll { $0.name == "title" }
            queryItems.append(URLQueryItem(name: "title", value: searchQuery))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func authenticatedRequest(
        url: URL,
        configuration: PlexConnectionConfiguration
    ) -> URLRequest {
        PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            accept: "application/json",
            token: configuration.token
        )
    }

    private func playbackDecision(
        configuration: PlexConnectionConfiguration,
        capabilities: PlexPlaybackCapabilities,
        mediaKind: PlexPlaybackMediaKind,
        sessionIdentifier: String,
        queryItems: [URLQueryItem]
    ) async throws -> PlexPlaybackDecisionContainer {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: mediaKind.decisionPath
        ), var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw PlexAPIError.invalidServerURL
        }

        var request = authenticatedRequest(url: url, configuration: configuration)
        request.setValue(sessionIdentifier, forHTTPHeaderField: "X-Plex-Session-Identifier")
        request.setValue("generic", forHTTPHeaderField: "X-Plex-Client-Profile-Name")
        request.setValue(
            capabilities.clientProfileExtra(for: mediaKind),
            forHTTPHeaderField: "X-Plex-Client-Profile-Extra"
        )

        do {
            let responseData = try await data(for: request)
            return try JSONDecoder()
                .decode(PlexPlaybackDecisionEnvelope.self, from: responseData)
                .mediaContainer
        } catch let error as PlexAPIError {
            throw error
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    private func playbackSelection(
        from decision: PlexPlaybackDecisionContainer,
        mediaKind: PlexPlaybackMediaKind
    ) throws -> PlexPlaybackSelection {
        switch PlexPlaybackDecisionResolver.resolve(decision, mediaKind: mediaKind) {
        case .selected(let selection):
            return selection
        case .rejected(let reason):
            throw PlexAPIError.playbackRejected(reason)
        case .noPlayableMedia:
            throw PlexAPIError.noPlayableMedia
        }
    }

    private func playbackURL(
        selection: PlexPlaybackSelection,
        configuration: PlexConnectionConfiguration,
        capabilities: PlexPlaybackCapabilities,
        mediaKind: PlexPlaybackMediaKind,
        sessionIdentifier: String,
        queryItems: [URLQueryItem]
    ) throws -> URL {
        var playbackQueryItems: [URLQueryItem] = switch selection.method {
        case .directPlay:
            []
        case .directStream, .transcode:
            queryItems
        }
        if selection.method != .directPlay {
            playbackQueryItems += [
                URLQueryItem(name: "X-Plex-Client-Profile-Name", value: "generic"),
                URLQueryItem(
                    name: "X-Plex-Client-Profile-Extra",
                    value: capabilities.clientProfileExtra(for: mediaKind)
                )
            ]
        }

        guard let url = authenticatedMediaURL(
            configuration: configuration,
            path: selection.path,
            sessionIdentifier: sessionIdentifier,
            queryItems: playbackQueryItems
        ) else {
            throw PlexAPIError.invalidServerURL
        }
        return url
    }

    private func authenticatedMediaURL(
        configuration: PlexConnectionConfiguration,
        path: String,
        sessionIdentifier: String,
        queryItems: [URLQueryItem]
    ) -> URL? {
        guard let endpoint = PlexURLBuilder.endpointURL(serverURL: configuration.serverURL, path: path),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let clientQueryItems = configuration.clientContext.headers
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = queryItems + clientQueryItems + [
            URLQueryItem(name: "X-Plex-Session-Identifier", value: sessionIdentifier),
            URLQueryItem(name: "X-Plex-Token", value: configuration.token)
        ]
        return components.url
    }
}
