import PlexClientKit
import PlexModels
import Foundation

actor TVPlexClient {
    private let session: URLSession
    private var providerEndpointsByServerIdentifier: [String: PlexLibraryProviderEndpoints] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(
        _ connection: TVPlexConnection,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> TVPlexServerIdentity {
        let data = try await data(
            path: "/identity",
            timeoutInterval: timeoutInterval,
            connection: connection
        )
        do {
            return try JSONDecoder().decode(TVPlexIdentityEnvelope.self, from: data).mediaContainer
        } catch {
            throw TVPlexError.decodingFailed
        }
    }

    func resolve(
        _ server: PlexServerResource,
        clientIdentifier: String
    ) async throws -> TVPlexResolvedServer {
        let connections = server.connections.sorted { lhs, rhs in
            if lhs.priorityTier != rhs.priorityTier {
                return lhs.priorityTier < rhs.priorityTier
            }

            let lhsIsHTTPS = lhs.uri.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame
            let rhsIsHTTPS = rhs.uri.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame
            if lhsIsHTTPS != rhsIsHTTPS {
                return lhsIsHTTPS
            }

            return lhs.uri.absoluteString.localizedCaseInsensitiveCompare(
                rhs.uri.absoluteString
            ) == .orderedAscending
        }

        var failureCodes: [URLError.Code] = []
        for advertisedConnection in connections {
            let candidate = TVPlexConnection(
                serverURL: advertisedConnection.uri,
                token: server.accessToken,
                clientIdentifier: clientIdentifier,
                serverIdentifier: server.id,
                kind: advertisedConnection.kind
            )
            do {
                let identity = try await validate(candidate, timeoutInterval: 2.5)
                guard let actualIdentifier = identity.machineIdentifier?.nilIfBlank else {
                    throw TVPlexError.invalidResponse
                }
                if actualIdentifier != server.id {
                    throw TVPlexError.serverIdentityMismatch(
                        expected: server.id,
                        actual: actualIdentifier
                    )
                }
                return TVPlexResolvedServer(connection: candidate, identity: identity)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError {
                guard error.isConnectivityFailure else { throw error }
                failureCodes.append(error.code)
            }
        }

        throw PlexServerConnectionFailure(serverName: server.name, failureCodes: failureCodes)
    }

    func fetchHome(connection: TVPlexConnection) async throws -> [PlexHub] {
        let endpoints = try await libraryProviderEndpoints(connection: connection)
        guard let promotedPath = endpoints.promotedPath else {
            throw PlexAPIError.missingLibraryPromotedFeature
        }
        guard let continueWatchingPath = endpoints.continueWatchingPath else {
            throw PlexAPIError.missingLibraryContinueWatchingFeature
        }
        async let promoted = fetchHomeHubs(path: promotedPath, connection: connection)
        async let continuation = fetchHomeHubs(path: continueWatchingPath, connection: connection)
        return TVHomeContent.hubs(try await PlexHub.homeHubs(promoted: promoted, continueWatching: continuation))
    }

    private func fetchHomeHubs(path: String, connection: TVPlexConnection) async throws -> [PlexHub] {
        let data = try await data(
            path: path,
            queryItems: [
                URLQueryItem(name: "count", value: "20"),
                URLQueryItem(name: "includeGuids", value: "1"),
                URLQueryItem(name: "includeMeta", value: "1"),
                URLQueryItem(name: "includeExternalMedia", value: "1")
            ],
            connection: connection
        )
        do {
            return try JSONDecoder().decode(PlexHubEnvelope.self, from: data).mediaContainer.hubs
        } catch {
            throw TVPlexError.decodingFailed
        }
    }

    func fetchLibraries(connection: TVPlexConnection) async throws -> [TVPlexLibrary] {
        let data = try await data(path: "/library/sections/all", connection: connection)
        let libraries: [TVPlexLibrary]
        do {
            libraries = try JSONDecoder().decode(TVPlexLibrariesEnvelope.self, from: data)
                .mediaContainer.directories
                .filter { ["movie", "show", "artist"].contains($0.type.lowercased()) }
        } catch {
            throw TVPlexError.decodingFailed
        }
        // Match macOS library summaries: the current library item supplies the
        // artwork when the server has no section composite image.
        return try await withThrowingTaskGroup(of: (Int, TVPlexLibrary).self) { group in
            for (index, library) in libraries.enumerated() {
                group.addTask {
                    let response = try await self.data(
                        path: "/library/sections/\(library.id)/all",
                        queryItems: [URLQueryItem(name: "sort", value: "addedAt:desc")],
                        headers: ["X-Plex-Container-Start": "0", "X-Plex-Container-Size": "1"],
                        connection: connection
                    )
                    let recent = try await self.decodeMediaPage(response).items.first
                    var library = library
                    library.recentArtworkPath = recent?.art?.nilIfBlank ?? recent?.thumb?.nilIfBlank
                    return (index, library)
                }
            }
            var result: [(Int, TVPlexLibrary)] = []
            for try await library in group { result.append(library) }
            return result.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func fetchLibrary(
        _ library: TVPlexLibrary,
        start: Int = 0,
        size: Int = 60,
        options: PlexLibraryBrowseOptions = .default,
        connection: TVPlexConnection
    ) async throws -> PlexMediaPage {
        let data = try await data(
            path: "/library/sections/\(library.id)/all",
            queryItems: options.queryItems + [
                URLQueryItem(name: "includeGuids", value: "1"),
                URLQueryItem(name: "includeMeta", value: "1")
            ],
            headers: [
                "X-Plex-Container-Start": String(start),
                "X-Plex-Container-Size": String(size)
            ],
            connection: connection
        )
        return try decodeMediaPage(data)
    }

    func fetchHubPage(path: String, start: Int, size: Int = 60, connection: TVPlexConnection) async throws -> PlexMediaPage {
        let response = try await data(
            path: path,
            headers: ["X-Plex-Container-Start": String(start), "X-Plex-Container-Size": String(size)],
            connection: connection
        )
        return try decodeMediaPage(response, defaultOffset: start)
    }

    func fetchLibraryBrowseDefinition(_ library: TVPlexLibrary, connection: TVPlexConnection) async throws -> PlexLibraryBrowseDefinition {
        let path = "/library/sections/\(library.id)"
        async let filters = data(path: path + "/filters", connection: connection)
        async let sorts = data(path: path + "/sorts", connection: connection)
        let responses = try await (filters, sorts)
        do {
            return try PlexLibraryBrowseDefinition(
                contentPath: path + "/all",
                filters: JSONDecoder().decode(PlexLibraryFilterEnvelope.self, from: responses.0).mediaContainer.filters,
                sorts: JSONDecoder().decode(PlexLibrarySortEnvelope.self, from: responses.1).mediaContainer.sorts
            )
        } catch {
            throw TVPlexError.decodingFailed
        }
    }

    func fetchLibraryFilterValues(_ filter: PlexLibraryFilterDefinition, connection: TVPlexConnection) async throws -> [PlexLibraryFilterValue] {
        guard let path = filter.valuesPath else { throw PlexAPIError.invalidResponse }
        let response = try await data(path: path, connection: connection)
        do {
            return try JSONDecoder().decode(PlexLibraryFilterValuesEnvelope.self, from: response)
                .mediaContainer.values(for: filter)
        } catch let error as PlexAPIError {
            throw error
        } catch {
            throw TVPlexError.decodingFailed
        }
    }

    func fetchMetadata(
        ratingKey: String,
        connection: TVPlexConnection
    ) async throws -> PlexMediaItem {
        try await fetchMetadata(
            path: "/library/metadata/\(ratingKey)",
            connection: connection
        )
    }

    func fetchMediaExtras(ratingKey: String, connection: TVPlexConnection) async throws -> [PlexMediaItem] {
        let response = try await data(path: "/library/metadata/\(ratingKey)/extras", connection: connection)
        return try decodeMediaPage(response).items
    }

    func fetchRelatedHubs(ratingKey: String, connection: TVPlexConnection) async throws -> [PlexHub] {
        let response = try await data(
            path: "/hubs/metadata/\(ratingKey)/related",
            queryItems: [URLQueryItem(name: "count", value: "12")],
            connection: connection
        )
        do {
            return try JSONDecoder().decode(PlexHubEnvelope.self, from: response)
                .mediaContainer.hubs.filter { !$0.metadata.isEmpty }
        } catch {
            throw TVPlexError.decodingFailed
        }
    }

    func fetchMetadata(
        path: String,
        connection: TVPlexConnection
    ) async throws -> PlexMediaItem {
        let data = try await data(
            path: path,
            queryItems: [
                URLQueryItem(name: "includeGuids", value: "1"),
                URLQueryItem(name: "includeConcerts", value: "1"),
                URLQueryItem(name: "includeExtras", value: "1"),
                URLQueryItem(name: "includeOptionalElements", value: "Chapter,Image,Marker,Rating")
            ],
            connection: connection
        )
        guard let item = try decodeMediaPage(data).items.first else {
            throw TVPlexError.invalidResponse
        }
        return item
    }

    func fetchEpisodeSeriesCast(
        for item: PlexMediaItem,
        connection: TVPlexConnection
    ) async throws -> [PlexTag] {
        guard let seriesRatingKey = item.episodeSeriesCastRatingKey else { return [] }
        let series = try await fetchMetadata(ratingKey: seriesRatingKey, connection: connection)
        guard series.ratingKey == seriesRatingKey,
              series.type?.caseInsensitiveCompare("show") == .orderedSame else {
            throw TVPlexError.invalidResponse
        }
        return series.roles
    }

    func fetchPerson(
        identifier: String,
        connection: TVPlexConnection
    ) async throws -> PlexTag {
        let data = try await data(
            path: "/library/people",
            appendingPathComponents: [identifier],
            connection: connection
        )
        do {
            guard let person = try JSONDecoder()
                .decode(PlexPeopleEnvelope.self, from: data)
                .mediaContainer
                .people
                .first else {
                throw TVPlexError.invalidResponse
            }
            return person
        } catch let error as TVPlexError {
            throw error
        } catch {
            throw TVPlexError.decodingFailed
        }
    }

    func fetchPersonMedia(
        identifier: String,
        connection: TVPlexConnection
    ) async throws -> [PlexMediaItem] {
        let data = try await data(
            path: "/library/people",
            appendingPathComponents: [identifier, "media"],
            connection: connection
        )
        return try decodeMediaPage(data).items
    }

    func fetchChildren(
        of item: PlexMediaItem,
        connection: TVPlexConnection
    ) async throws -> [PlexMediaItem] {
        try await fetchChildren(ratingKey: item.ratingKey, connection: connection)
    }

    func fetchNextEpisode(
        after item: PlexMediaItem,
        connection: TVPlexConnection
    ) async throws -> PlexMediaItem? {
        guard item.type?.lowercased() == "episode",
              let seasonRatingKey = item.parentRatingKey else {
            return nil
        }

        let seasonEpisodes = try await fetchChildren(
            ratingKey: seasonRatingKey,
            connection: connection
        ).filter { $0.type?.lowercased() == "episode" }
        if let next = PlexEpisodeContinuity.nextEpisode(after: item, in: seasonEpisodes) {
            return next
        }

        guard let showRatingKey = item.grandparentRatingKey else {
            return nil
        }
        let seasons = try await fetchChildren(
            ratingKey: showRatingKey,
            connection: connection
        ).filter { $0.type?.lowercased() == "season" }
        guard let nextSeason = PlexEpisodeContinuity.nextSeason(
            afterRatingKey: seasonRatingKey,
            index: item.parentIndex,
            in: seasons
        ) else {
            return nil
        }

        let nextSeasonEpisodes = try await fetchChildren(
            ratingKey: nextSeason.ratingKey,
            connection: connection
        )
        .filter { $0.type?.lowercased() == "episode" }
        return PlexEpisodeContinuity.ordered(nextSeasonEpisodes).first
    }

    func createContinuousPlayQueue(
        for item: PlexMediaItem,
        connection: TVPlexConnection
    ) async throws -> PlexPlaybackQueue {
        let endpoints = try await libraryProviderEndpoints(connection: connection)
        guard let playQueuePath = endpoints.playQueuePath else {
            throw PlexAPIError.missingLibraryPlayQueueFeature
        }
        let queueRequest = try PlexContinuousPlayQueueRequest(
            item: item,
            serverIdentifier: connection.serverIdentifier,
            providerIdentifier: endpoints.providerIdentifier
        )
        let data = try await data(
            path: playQueuePath,
            queryItems: queueRequest.queryItems,
            method: "POST",
            connection: connection
        )
        let page = try decodePlayQueuePage(data)
        return try PlexPlaybackQueue(
            page: page,
            selectedRatingKey: item.ratingKey
        )
    }

    func createCinemaPlayQueue(
        for item: PlexMediaItem,
        extrasPrefixCount: Int,
        connection: TVPlexConnection
    ) async throws -> PlexPlaybackQueue {
        let endpoints = try await libraryProviderEndpoints(connection: connection)
        guard let playQueuePath = endpoints.playQueuePath else {
            throw PlexAPIError.missingLibraryPlayQueueFeature
        }
        let queueRequest = try PlexCinemaPlayQueueRequest(
            item: item,
            extrasPrefixCount: extrasPrefixCount,
            serverIdentifier: connection.serverIdentifier,
            providerIdentifier: endpoints.providerIdentifier
        )
        let data = try await data(
            path: playQueuePath,
            queryItems: queueRequest.queryItems,
            method: "POST",
            connection: connection
        )
        let page = try decodePlayQueuePage(data)
        guard page.selectedItemID?.nilIfBlank != nil else {
            throw PlexAPIError.invalidPlayQueue
        }
        return try PlexPlaybackQueue(
            page: page,
            selectedRatingKey: item.ratingKey,
            purpose: .cinemaPreplay(primaryRatingKey: item.ratingKey)
        )
    }

    func fetchPlayQueuePage(
        queueID: Int,
        centeredOn playQueueItemID: String,
        window: Int = 50,
        connection: TVPlexConnection
    ) async throws -> PlexPlayQueuePage {
        guard queueID > 0,
              let playQueueItemID = playQueueItemID.nilIfBlank else {
            throw PlexAPIError.invalidPlayQueue
        }
        let endpoints = try await libraryProviderEndpoints(connection: connection)
        guard let playQueuePath = endpoints.playQueuePath else {
            throw PlexAPIError.missingLibraryPlayQueueFeature
        }
        let data = try await data(
            path: playQueuePath,
            appendingPathComponents: [String(queueID)],
            queryItems: [
                URLQueryItem(name: "center", value: playQueueItemID),
                URLQueryItem(name: "window", value: String(max(window, 1))),
                URLQueryItem(name: "includeBefore", value: "1"),
                URLQueryItem(name: "includeAfter", value: "1"),
            ],
            connection: connection
        )
        return try decodePlayQueuePage(data)
    }

    func setPlayQueueShuffled(
        _ shuffled: Bool,
        queueID: Int,
        connection: TVPlexConnection
    ) async throws -> PlexPlayQueuePage {
        let mutation = try PlexPlayQueueMutationRequest(
            queueID: queueID,
            mutation: .shuffled(shuffled)
        )
        let endpoints = try await libraryProviderEndpoints(connection: connection)
        guard let playQueuePath = endpoints.playQueuePath else {
            throw PlexAPIError.missingLibraryPlayQueueFeature
        }
        let data = try await data(
            path: playQueuePath,
            appendingPathComponents: mutation.endpointPathComponents,
            method: "PUT",
            connection: connection
        )
        return try decodePlayQueuePage(data)
    }

    func removePlayQueueItem(
        queueID: Int,
        playQueueItemID: String,
        connection: TVPlexConnection
    ) async throws -> PlexPlayQueuePage {
        let mutation = try PlexPlayQueueItemMutationRequest(
            queueID: queueID,
            mutation: .remove(playQueueItemID: playQueueItemID)
        )
        let endpoints = try await libraryProviderEndpoints(connection: connection)
        guard let playQueuePath = endpoints.playQueuePath else {
            throw PlexAPIError.missingLibraryPlayQueueFeature
        }
        let data = try await data(
            path: playQueuePath,
            appendingPathComponents: mutation.endpointPathComponents,
            method: mutation.method,
            connection: connection
        )
        return try decodePlayQueuePage(data)
    }

    func movePlayQueueItem(
        queueID: Int,
        move: PlexPlayQueueItemMove,
        connection: TVPlexConnection
    ) async throws -> PlexPlayQueuePage {
        let mutation = try PlexPlayQueueItemMutationRequest(
            queueID: queueID,
            mutation: .move(move)
        )
        let endpoints = try await libraryProviderEndpoints(connection: connection)
        guard let playQueuePath = endpoints.playQueuePath else {
            throw PlexAPIError.missingLibraryPlayQueueFeature
        }
        let data = try await data(
            path: playQueuePath,
            appendingPathComponents: mutation.endpointPathComponents,
            queryItems: mutation.queryItems,
            method: mutation.method,
            connection: connection
        )
        return try decodePlayQueuePage(data)
    }

    func resetPlayQueue(
        queueID: Int,
        connection: TVPlexConnection
    ) async throws -> PlexPlayQueuePage {
        let mutation = try PlexPlayQueueMutationRequest(
            queueID: queueID,
            mutation: .reset
        )
        let endpoints = try await libraryProviderEndpoints(connection: connection)
        guard let playQueuePath = endpoints.playQueuePath else {
            throw PlexAPIError.missingLibraryPlayQueueFeature
        }
        let data = try await data(
            path: playQueuePath,
            appendingPathComponents: mutation.endpointPathComponents,
            method: "PUT",
            connection: connection
        )
        return try decodePlayQueuePage(data)
    }

    func search(
        query: String,
        connection: TVPlexConnection
    ) async throws -> [PlexHub] {
        let endpoints = try await libraryProviderEndpoints(connection: connection)
        guard let searchPath = endpoints.searchPath else { throw PlexAPIError.missingLibrarySearchFeature }
        let data = try await data(
            path: searchPath,
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "limit", value: "60"),
                URLQueryItem(name: "includeCollections", value: "1"),
                URLQueryItem(name: "includeExternalMedia", value: "0")
            ],
            connection: connection
        )
        do {
            return try JSONDecoder().decode(PlexHubEnvelope.self, from: data)
                .mediaContainer.hubs
                .filter { !$0.metadata.isEmpty }
        } catch {
            throw TVPlexError.decodingFailed
        }
    }

    func playbackPlan(
        for item: PlexMediaItem,
        startTime: TimeInterval,
        sessionIdentifier: String,
        videoQuality: PlexVideoQuality,
        musicQuality: PlexMusicQuality,
        audioBoost: PlexAudioBoost,
        streamingPolicy: PlexPlaybackStreamingPolicy,
        subtitleBurnMode: PlexSubtitleBurnMode,
        subtitleSize: PlexSubtitleSize,
        automaticallySyncSubtitles: Bool,
        automaticallyAdjustVideoQuality: Bool,
        playSmallerVideosAtOriginalQuality: Bool,
        forceVideoTranscode: Bool,
        source requestedSource: PlexPlaybackSource? = nil,
        forceServerMediaSelection: Bool = false,
        connection: TVPlexConnection
    ) async throws -> PlexPlaybackPlan {
        guard item.isPlayable,
              let source = requestedSource ?? item.defaultPlaybackSource,
              item.playbackSource(mediaIndex: source.mediaIndex) == source else {
            throw TVPlexError.noPlayableMedia
        }

        let capabilities = NativePlaybackCapabilityProbe.current()
        let mediaKind = PlexPlaybackMediaKind(media: item.media[source.mediaIndex])
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

        if streamingPolicy.forceDirectPlay,
           requestParameters.permitsDirectPlay,
           let path = capabilities.directPlayPath(for: item, source: source) {
            let url = try playbackURL(
                path: path,
                queryItems: [],
                sessionIdentifier: sessionIdentifier,
                connection: connection
            )
            return PlexPlaybackPlan(
                url: url,
                method: .directPlay,
                mediaKind: mediaKind,
                sessionIdentifier: sessionIdentifier,
                ratingKey: item.ratingKey,
                duration: item.duration.map { TimeInterval($0) / 1_000 },
                startTime: max(startTime.isFinite ? startTime : 0, 0),
                source: source,
                usesServerMediaSelection: false
            )
        }

        let queryItems = requestParameters.queryItems
        let decisionData = try await data(
            path: mediaKind.decisionPath,
            queryItems: queryItems,
            headers: [
                "X-Plex-Session-Identifier": sessionIdentifier,
                "X-Plex-Client-Profile-Name": "generic",
                "X-Plex-Client-Profile-Extra": capabilities.clientProfileExtra(for: mediaKind)
            ],
            connection: connection
        )
        let decision: PlexPlaybackDecisionContainer
        do {
            decision = try JSONDecoder()
                .decode(PlexPlaybackDecisionEnvelope.self, from: decisionData)
                .mediaContainer
        } catch {
            throw TVPlexError.decodingFailed
        }

        let selection: PlexPlaybackSelection
        switch PlexPlaybackDecisionResolver.resolve(decision, mediaKind: mediaKind) {
        case .selected(let value):
            selection = value
        case .rejected(let reason):
            throw TVPlexError.playbackRejected(reason)
        case .noPlayableMedia:
            throw TVPlexError.noPlayableMedia
        }

        let playbackQueryItems: [URLQueryItem] = switch selection.method {
        case .directPlay:
            []
        case .directStream, .transcode:
            queryItems + [
                URLQueryItem(name: "X-Plex-Client-Profile-Name", value: "generic"),
                URLQueryItem(
                    name: "X-Plex-Client-Profile-Extra",
                    value: capabilities.clientProfileExtra(for: mediaKind)
                )
            ]
        }
        let url = try playbackURL(
            path: selection.path,
            queryItems: playbackQueryItems,
            sessionIdentifier: sessionIdentifier,
            connection: connection
        )
        return PlexPlaybackPlan(
            url: url,
            method: selection.method,
            mediaKind: mediaKind,
            sessionIdentifier: sessionIdentifier,
            ratingKey: item.ratingKey,
            duration: item.duration.map { TimeInterval($0) / 1_000 },
            startTime: max(startTime.isFinite ? startTime : 0, 0),
            source: source,
            usesServerMediaSelection: forceServerMediaSelection,
            supportsAudioBoost: selection.supportsAudioBoost
                && requestParameters.hasMultichannelAudioSource,
            supportsSubtitleAutoSync: requestParameters.supportsSubtitleAutoSync
        )
    }

    private func playbackURL(
        path: String,
        queryItems: [URLQueryItem],
        sessionIdentifier: String,
        connection: TVPlexConnection
    ) throws -> URL {
        var authenticatedQueryItems = queryItems
        authenticatedQueryItems += PlexClientContext(
            clientIdentifier: connection.clientIdentifier
        ).headers
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        authenticatedQueryItems += [
            URLQueryItem(name: "X-Plex-Session-Identifier", value: sessionIdentifier),
            URLQueryItem(name: "X-Plex-Token", value: connection.token),
        ]
        return try endpoint(
            path: path,
            queryItems: authenticatedQueryItems,
            connection: connection
        )
    }

    func artworkURL(
        path: String?,
        width: Int,
        height: Int,
        connection: TVPlexConnection,
        usesOriginalImage: Bool = false
    ) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        // Clear logos must retain their original alpha channel. The photo
        // transcode endpoint used by posters explicitly produces JPEG.
        let imageURL = usesOriginalImage
            ? PlexURLBuilder.mediaURL(serverURL: connection.serverURL, path: path)
            : PlexURLBuilder.transcodedPhotoURL(
                serverURL: connection.serverURL,
                path: path,
                width: width,
                height: height
            )
        guard let imageURL,
              var components = URLComponents(url: imageURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "X-Plex-Token", value: connection.token)
        ]
        return components.url
    }

    func fetchArtworkData(
        path: String,
        width: Int,
        height: Int,
        connection: TVPlexConnection,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> Data {
        guard let url = artworkURL(
            path: path,
            width: width,
            height: height,
            connection: connection
        ) else {
            throw TVPlexError.invalidServerURL
        }
        var request = PlexRequestBuilder(
            clientContext: PlexClientContext(clientIdentifier: connection.clientIdentifier)
        ).request(url: url, accept: "image/*", token: connection.token)
        if let timeoutInterval { request.timeoutInterval = timeoutInterval }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TVPlexError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw TVPlexError.badStatus(response.statusCode)
        }
        guard !data.isEmpty else {
            throw TVPlexError.invalidResponse
        }
        return data
    }

    func selectMediaStreams(
        partID: Int,
        audioStreamID: Int? = nil,
        subtitleStreamID: Int? = nil,
        connection: TVPlexConnection
    ) async throws {
        let parameters = PlexMediaSelectionRequestParameters(
            partID: partID,
            audioStreamID: audioStreamID,
            subtitleStreamID: subtitleStreamID,
            allParts: true
        )
        guard parameters.hasSelection else {
            throw TVPlexError.invalidResponse
        }
        _ = try await data(
            path: parameters.path,
            queryItems: parameters.queryItems,
            method: "PUT",
            connection: connection
        )
    }

    func setSubtitleOffset(
        streamID: Int,
        milliseconds: Int,
        connection: TVPlexConnection
    ) async throws {
        let parameters = PlexSubtitleOffsetRequestParameters(
            streamID: streamID,
            milliseconds: milliseconds
        )
        _ = try await data(
            path: parameters.path,
            queryItems: parameters.queryItems,
            method: "PUT",
            connection: connection
        )
    }

    func reportTimeline(
        _ update: PlexTimelineUpdate,
        connection: TVPlexConnection
    ) async -> PlexTimelineResponse? {
        guard let endpoints = try? await libraryProviderEndpoints(connection: connection),
              let timelinePath = endpoints.timelinePath,
              let data = try? await data(
            path: timelinePath,
            queryItems: PlexTimelineRequestParameters(update: update).queryItems,
            headers: ["X-Plex-Session-Identifier": update.sessionIdentifier],
            method: "POST",
            connection: connection
        ) else {
            return nil
        }
        return try? JSONDecoder()
            .decode(PlexTimelineResponseEnvelope.self, from: data)
            .mediaContainer
            .response
    }

    func markWatched(_ item: PlexMediaItem, connection: TVPlexConnection) async throws {
        let endpoints = try await libraryProviderEndpoints(connection: connection)
        let parameters = try PlexWatchedStateRequestParameters(
            watched: true,
            ratingKey: item.ratingKey,
            endpoints: endpoints
        )
        try Task.checkCancellation()
        _ = try await data(
            path: parameters.endpointPath,
            queryItems: parameters.queryItems,
            method: "PUT",
            connection: connection
        )
    }

    private func decodeMediaPage(_ data: Data, defaultOffset: Int = 0) throws -> PlexMediaPage {
        do {
            let container = try JSONDecoder().decode(PlexMediaEnvelope.self, from: data).mediaContainer
            return PlexMediaPage(
                items: container.metadata,
                offset: container.offset ?? defaultOffset,
                totalSize: container.totalSize
            )
        } catch {
            throw TVPlexError.decodingFailed
        }
    }

    private func decodePlayQueuePage(_ data: Data) throws -> PlexPlayQueuePage {
        do {
            return try JSONDecoder()
                .decode(PlexPlayQueueEnvelope.self, from: data)
                .mediaContainer
                .page()
        } catch let error as PlexAPIError {
            throw error
        } catch {
            throw TVPlexError.decodingFailed
        }
    }

    private func libraryProviderEndpoints(
        connection: TVPlexConnection
    ) async throws -> PlexLibraryProviderEndpoints {
        if let cached = providerEndpointsByServerIdentifier[connection.serverIdentifier] {
            return cached
        }
        let data = try await data(path: "/media/providers", connection: connection)
        do {
            let endpoints = try JSONDecoder()
                .decode(PlexMediaProvidersEnvelope.self, from: data)
                .mediaContainer
                .libraryProviderEndpoints()
            providerEndpointsByServerIdentifier[connection.serverIdentifier] = endpoints
            return endpoints
        } catch let error as PlexAPIError {
            throw error
        } catch {
            throw TVPlexError.decodingFailed
        }
    }

    func fetchChildren(
        ratingKey: String,
        connection: TVPlexConnection
    ) async throws -> [PlexMediaItem] {
        let data = try await data(
            path: "/library/metadata/\(ratingKey)/children",
            headers: ["X-Plex-Container-Size": "500"],
            connection: connection
        )
        return try decodeMediaPage(data).items
    }

    private func data(
        path: String,
        appendingPathComponents: [String] = [],
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        method: String = "GET",
        timeoutInterval: TimeInterval? = nil,
        connection: TVPlexConnection
    ) async throws -> Data {
        let url = try endpoint(
            path: path,
            appendingPathComponents: appendingPathComponents,
            queryItems: queryItems,
            connection: connection
        )
        var request = PlexRequestBuilder(
            clientContext: PlexClientContext(clientIdentifier: connection.clientIdentifier)
        ).request(url: url, accept: "application/json", token: connection.token)
        request.httpMethod = method
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TVPlexError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw TVPlexError.badStatus(response.statusCode)
        }
        return data
    }

    private func endpoint(
        path: String,
        appendingPathComponents: [String] = [],
        queryItems: [URLQueryItem] = [],
        connection: TVPlexConnection
    ) throws -> URL {
        let endpoint = if appendingPathComponents.isEmpty {
            PlexURLBuilder.endpointURL(
                serverURL: connection.serverURL,
                path: path
            )
        } else {
            PlexURLBuilder.endpointURL(
                serverURL: connection.serverURL,
                path: path,
                appendingPathComponents: appendingPathComponents
            )
        }
        guard let endpoint,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw TVPlexError.invalidServerURL
        }
        components.queryItems = (components.queryItems ?? []) + queryItems
        guard let url = components.url else {
            throw TVPlexError.invalidServerURL
        }
        return url
    }

}

private extension URLError {
    var isConnectivityFailure: Bool {
        switch code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .secureConnectionFailed,
             .cannotLoadFromNetwork:
            true
        default:
            false
        }
    }
}
