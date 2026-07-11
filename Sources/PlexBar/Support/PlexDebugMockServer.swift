import AppKit
import Foundation

enum PlexDebugMockServer {
    static var mockUserToken: String {
        #if DEBUG
        return debugFixture.userToken
        #else
        preconditionFailure("Mock runtime is only available in DEBUG builds.")
        #endif
    }

    static var mockServer: PlexServerResource {
        #if DEBUG
        return debugFixture.server
        #else
        preconditionFailure("Mock runtime is only available in DEBUG builds.")
        #endif
    }

    static var mockResolvedConnection: PlexResolvedConnection {
        #if DEBUG
        return debugFixture.activeConnection
        #else
        preconditionFailure("Mock runtime is only available in DEBUG builds.")
        #endif
    }

    static func makeSession() -> URLSession {
        #if DEBUG
        debugFixture.seedArtworkCache()
        let stateID = PlexDebugMockStateRegistry.shared.register(PlexDebugMockState())
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [PlexDebugMockStateRegistry.headerName: stateID]
        configuration.protocolClasses = [PlexDebugMockURLProtocol.self]
        return URLSession(configuration: configuration)
        #else
        return .shared
        #endif
    }

    static func makeEventsClient(liveClient: PlexSessionEventsClient = PlexSessionEventsClient()) -> PlexSessionEventsClient {
        #if DEBUG
        return PlexSessionEventsClient { configuration, onEvent in
            guard configuration.serverURL.host == debugFixture.server.connections[0].uri.host else {
                try await liveClient.monitor(using: configuration, onEvent: onEvent)
                return
            }

            try await onEvent(.connected)

            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(3_600))
            }

            throw CancellationError()
        }
        #else
        return liveClient
        #endif
    }

}

#if DEBUG
private let debugFixture = PlexDebugMockFixture.makeDefault()

private struct PlexDebugMockFixture {
    let userToken: String
    let authenticatedUser: PlexAuthenticatedUser
    let server: PlexServerResource
    let activeConnection: PlexResolvedConnection
    let sessions: [PlexSession]
    let activeSessionPayloadsByKey: [String: PlexMockServerPayload.ActiveSession]
    let streamLevelsByID: [Int: [Double]]
    let resolvedLocationsBySessionKey: [String: String]
    let historyItems: [PlexHistoryItem]
    let metadataItems: [PlexMetadataItem]
    let accountsByID: [Int: PlexAccount]
    let librarySections: [PlexDebugMockLibrarySection]
    let snapshotDate: Date
    let seededArtwork: [DebugSeededArtwork]

    var libraries: [PlexLibrary] {
        librarySections.map(\.library)
    }

    static func makeDefault() -> PlexDebugMockFixture {
        let payload = try! PlexMockServerPayload.loadDefault()
        let snapshotDate = Date()
        let userToken = "plexbar-debug-mock-user-token"
        let server = payload.server.materialize()
        let serverURL = server.connections[0].uri
        let usersByID = Dictionary(uniqueKeysWithValues: payload.users.map { ($0.id, $0) })
        let moviesByID = Dictionary(uniqueKeysWithValues: payload.movies.map { ($0.id, $0) })
        let showsByID = Dictionary(uniqueKeysWithValues: payload.shows.map { ($0.id, $0) })
        let episodesByID = Dictionary(uniqueKeysWithValues: payload.episodes.map { ($0.id, $0) })
        let audiobooksByID = Dictionary(uniqueKeysWithValues: payload.audiobooks.map { ($0.id, $0) })

        let activeConnection = PlexResolvedConnection(
            serverID: server.id,
            url: serverURL,
            kind: .local,
            validatedAt: snapshotDate
        )
        let authenticatedUser = payload.authenticatedUser.materialize(
            thumbOverride: localAvatarResourceURL(for: payload.authenticatedUser.thumb)?.absoluteString
        )

        let accountsByID = Dictionary(
            uniqueKeysWithValues: payload.users.map { userPayload in
                let account = userPayload.materialize()
                return (account.id, account)
            }
        )
        let sessions = payload.activeSessions.map {
            materializeSession(
                $0,
                usersByID: usersByID,
                moviesByID: moviesByID,
                showsByID: showsByID,
                episodesByID: episodesByID,
                audiobooksByID: audiobooksByID
            )
        }
        let historyItems = payload.historyEvents.map {
            materializeHistoryItem(
                $0,
                referenceDate: snapshotDate,
                moviesByID: moviesByID,
                showsByID: showsByID,
                episodesByID: episodesByID
            )
        }
        let metadataItems = payload.episodes.map { materializeMetadataItem($0, showsByID: showsByID) }
        let librarySections = payload.libraries.map {
            materializeLibrarySection(
                $0,
                referenceDate: snapshotDate,
                moviesByID: moviesByID,
                showsByID: showsByID,
                audiobooksByID: audiobooksByID
            )
        }

        return PlexDebugMockFixture(
            userToken: userToken,
            authenticatedUser: authenticatedUser,
            server: server,
            activeConnection: activeConnection,
            sessions: sessions,
            activeSessionPayloadsByKey: Dictionary(
                uniqueKeysWithValues: payload.activeSessions.map { ($0.sessionKey, $0) }
            ),
            streamLevelsByID: Dictionary(
                payload.activeSessions.compactMap { session in
                    session.audioStream.map { ($0.id, $0.levels) }
                },
                uniquingKeysWith: { existing, _ in existing }
            ),
            resolvedLocationsBySessionKey: payload.resolvedLocationsBySessionKey,
            historyItems: historyItems,
            metadataItems: metadataItems,
            accountsByID: accountsByID,
            librarySections: librarySections,
            snapshotDate: snapshotDate,
            seededArtwork: [
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/avatars/dana-scully.png", sourceFileName: "dana-scully.png"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/avatars/darlene-alderson.png", sourceFileName: "darlene-alderson.png"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/avatars/elliot-alderson.png", sourceFileName: "elliot-alderson.png"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/avatars/le-petit-prince.png", sourceFileName: "le-petit-prince.png"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/avatars/popeye.png", sourceFileName: "popeye.png"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/avatars/scrump-toggins.png", sourceFileName: "scrump-toggins.png"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/avatars/tommy-shelby.png", sourceFileName: "tommy-shelby.png"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/art/movies/charade.png", sourceFileName: "charade.png", resourceDirectory: "Resources/MockServer/art/movies"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/art/movies/night-of-the-living-dead.png", sourceFileName: "night-of-the-living-dead.png", resourceDirectory: "Resources/MockServer/art/movies"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/art/movies/sherlock-jr.png", sourceFileName: "sherlock-jr.png", resourceDirectory: "Resources/MockServer/art/movies"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/art/tv/one-step-beyond.png", sourceFileName: "one-step-beyond.png", resourceDirectory: "Resources/MockServer/art/tv"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/art/tv/adventures-of-ozzie-and-harriet.png", sourceFileName: "adventures-of-ozzie-and-harriet.png", resourceDirectory: "Resources/MockServer/art/tv"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/art/tv/abbott-and-costello.png", sourceFileName: "abbott-and-costello.png", resourceDirectory: "Resources/MockServer/art/tv"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/art/audiobooks/dracula.png", sourceFileName: "dracula.png", resourceDirectory: "Resources/MockServer/art/audiobooks"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/art/audiobooks/the-time-machine.png", sourceFileName: "the-time-machine.png", resourceDirectory: "Resources/MockServer/art/audiobooks"),
                DebugSeededArtwork.load(serverURL: serverURL, mockPath: "/mock/art/audiobooks/war-of-the-worlds.png", sourceFileName: "war-of-the-worlds.png", resourceDirectory: "Resources/MockServer/art/audiobooks"),
            ]
        )
    }

    func seedArtworkCache() {
        let cache = PlexImageMemoryCache.shared

        for artwork in seededArtwork {
            guard let cgImage = artwork.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }

            let cacheKey = "\(artwork.url.absoluteString)|\(server.accessToken)"
            cache.insert(artwork.image, for: cacheKey)
            cache.insert(cgImage, for: cacheKey)

            if let localURL = Self.localAvatarResourceURL(for: artwork.url.path),
               localURL.absoluteString == authenticatedUser.thumb {
                cache.insert(artwork.image, for: localURL.absoluteString)
                cache.insert(cgImage, for: localURL.absoluteString)
            }
        }
    }

    private static func localAvatarResourceURL(for thumb: String?) -> URL? {
        guard let thumb = thumb?.nilIfBlank else {
            return nil
        }

        return PlexMockServerResourceLocator.url(for: "avatars/\(URL(fileURLWithPath: thumb).lastPathComponent)")
    }

    func response(for request: URLRequest, state: PlexDebugMockState) -> PlexDebugMockResponse? {
        guard let url = request.url else {
            return nil
        }

        if isMockServer(url) {
            return serverResponse(for: request, state: state)
        }

        if PlexRemoteService.isPlexHosted(url) {
            return remoteResponse(for: request)
        }

        return nil
    }

    private func isMockServer(_ url: URL) -> Bool {
        let fixtureURL = activeConnection.url
        return url.scheme == fixtureURL.scheme && url.host == fixtureURL.host && url.port == fixtureURL.port
    }

    private func serverResponse(for request: URLRequest, state: PlexDebugMockState) -> PlexDebugMockResponse? {
        guard let url = request.url else {
            return nil
        }

        if url.path == "/photo/:/transcode" {
            return transcodedImageResponse(for: url)
        }

        if url.path.hasPrefix("/mock/avatars/") || url.path.hasPrefix("/mock/art/") {
            return imageResponse(for: url)
        }

        if url.path == "/identity" {
            return jsonResponse(
                url: url,
                object: [
                    "MediaContainer": [
                        "claimed": true,
                        "machineIdentifier": server.id,
                        "version": server.productVersion ?? ""
                    ]
                ]
            )
        }

        if url.path == "/status/sessions" {
            let sessionKey = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "sessionKey" })?
                .value
            let filteredSessions = sessions.filter { session in
                guard state.isTerminated(session) == false else {
                    return false
                }

                guard let sessionKey else {
                    return true
                }

                return session.canonicalSessionKey == sessionKey
            }
            return jsonResponse(
                url: url,
                object: [
                    "MediaContainer": [
                        "Metadata": filteredSessions.map { session in
                            sessionObject(from: session, payload: session.canonicalSessionKey.flatMap { activeSessionPayloadsByKey[$0] })
                        }
                    ]
                ]
            )
        }

        if url.path == "/status/sessions/terminate" {
            if let sessionID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "sessionId" })?
                .value {
                state.terminateSession(withID: sessionID)
            }

            return jsonResponse(url: url, object: ["MediaContainer": [:]])
        }

        if let streamID = streamID(forLevelsPath: url.path),
           let levels = streamLevelsByID[streamID] {
            return jsonResponse(
                url: url,
                object: [
                    "MediaContainer": [
                        "size": levels.count,
                        "totalSamples": String(levels.count),
                        "Level": levels.map { ["v": $0] }
                    ]
                ]
            )
        }

        if url.path == "/status/sessions/history/all" {
            return jsonResponse(
                url: url,
                object: [
                    "MediaContainer": [
                        "Metadata": historyItems.map { historyItemObject(from: $0) }
                    ]
                ],
                headers: ["X-Plex-Container-Total-Size": String(historyItems.count)]
            )
        }

        if let metadataIDs = metadataIDs(for: url.path) {
            let metadata = metadataItems
                .filter { metadataIDs.contains($0.ratingKey) }
                .map(metadataItemObject(from:))
            return jsonResponse(
                url: url,
                object: [
                    "MediaContainer": [
                        "Metadata": metadata
                    ]
                ]
            )
        }

        if url.path == "/statistics/media" {
            let accounts = accountsByID.keys.sorted().compactMap { accountsByID[$0] }.map { accountObject(from: $0) }
            return jsonResponse(
                url: url,
                object: [
                    "MediaContainer": [
                        "Account": accounts
                    ]
                ]
            )
        }

        if url.path == "/library/sections/all" {
            return jsonResponse(
                url: url,
                object: [
                    "MediaContainer": [
                        "Directory": librarySections.map { libraryDirectoryObject(from: $0) }
                    ]
                ]
            )
        }

        if let libraryID = libraryID(for: url.path),
           let librarySection = librarySections.first(where: { $0.library.id == libraryID }) {
            let requestedType = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "type" })?
                .value
                .flatMap(Int.init)
            let containerStart = Int(request.value(forHTTPHeaderField: "X-Plex-Container-Start") ?? "") ?? 0
            let containerSize = Int(request.value(forHTTPHeaderField: "X-Plex-Container-Size") ?? "") ?? 1

            let totalSize = requestedType.flatMap { librarySection.countOverrides[$0] } ?? librarySection.library.itemCount
            let metadata = if requestedType == nil && containerSize != 0 {
                Array(
                    librarySection.recentItems
                        .dropFirst(containerStart)
                        .prefix(containerSize)
                        .map(libraryRecentItemObject(from:))
                )
            } else {
                []
            }

            return jsonResponse(
                url: url,
                object: [
                    "MediaContainer": [
                        "size": metadata.count,
                        "totalSize": totalSize,
                        "Metadata": metadata
                    ]
                ],
                headers: ["X-Plex-Container-Total-Size": String(totalSize)]
            )
        }

        return nil
    }

    private func remoteResponse(for request: URLRequest) -> PlexDebugMockResponse? {
        guard let url = request.url else {
            return nil
        }

        if url.path == "/api/v2/user" {
            return jsonResponse(
                url: url,
                object: compactObject([
                    "id": authenticatedUser.id,
                    "username": authenticatedUser.username,
                    "title": authenticatedUser.title,
                    "email": authenticatedUser.email,
                    "thumb": authenticatedUser.thumb,
                    "friendlyName": authenticatedUser.friendlyName,
                ])
            )
        }

        if url.path == "/api/resources" {
            return serverResourcesResponse(for: url)
        }

        if url.path == "/api/v2/pins" {
            return jsonResponse(
                url: url,
                object: [
                    "id": 4242,
                    "code": "PLEXBAR-MOCK",
                    "authToken": NSNull()
                ]
            )
        }

        if url.path.hasPrefix("/api/v2/pins/") {
            return jsonResponse(
                url: url,
                object: [
                    "id": 4242,
                    "code": "PLEXBAR-MOCK",
                    "authToken": userToken
                ]
            )
        }

        if url.path == "/api/v2/geoip" {
            return geoIPResponse(for: url)
        }

        return nil
    }

    private func geoIPResponse(for url: URL) -> PlexDebugMockResponse? {
        guard let ipAddress = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "ip_address" })?
            .value else {
            return nil
        }

        let location = sessions
            .first(where: { $0.geoLookupIPAddress == ipAddress })
            .flatMap { session in
                session.canonicalSessionKey.flatMap { resolvedLocationsBySessionKey[$0] }
            }

        let xml: String
        if let location {
            let parts = location.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2, parts[1].count <= 3 {
                xml = "<MediaContainer><location city=\"\(xmlEscaped(parts[0]))\" subdivisions=\"\(xmlEscaped(parts[1]))\" /></MediaContainer>"
            } else if parts.count == 2 {
                xml = "<MediaContainer><location city=\"\(xmlEscaped(parts[0]))\" country=\"\(xmlEscaped(parts[1]))\" /></MediaContainer>"
            } else {
                xml = "<MediaContainer><location city=\"\(xmlEscaped(location))\" /></MediaContainer>"
            }
        } else {
            xml = "<MediaContainer />"
        }

        let data = Data(xml.utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/xml"])!
        return PlexDebugMockResponse(response: response, data: data)
    }

    private func imageResponse(for url: URL) -> PlexDebugMockResponse? {
        guard let artwork = seededArtwork.first(where: { $0.url.path == url.path }) else {
            return nil
        }

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
        return PlexDebugMockResponse(response: response, data: artwork.data)
    }

    private func transcodedImageResponse(for url: URL) -> PlexDebugMockResponse? {
        guard let sourcePath = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "url" })?
            .value,
              sourcePath.hasPrefix("/mock/") else {
            return nil
        }

        guard let sourceURL = PlexURLBuilder.mediaURL(serverURL: activeConnection.url, path: sourcePath) else {
            return nil
        }

        return imageResponse(for: sourceURL)
    }

    private func serverResourcesResponse(for url: URL) -> PlexDebugMockResponse? {
        let connectionsXML = server.connections.map { connection in
            """
            <Connection uri="\(xmlEscaped(connection.uri.absoluteString))" local="\(connection.local ? "1" : "0")" relay="\(connection.relay ? "1" : "0")" />
            """
        }
        .joined()

        let productVersionAttribute = server.productVersion.map {
            " productVersion=\"\(xmlEscaped($0))\""
        } ?? ""
        let xml = """
        <MediaContainer size="1">
          <Device name="\(xmlEscaped(server.name))" clientIdentifier="\(xmlEscaped(server.id))" accessToken="\(xmlEscaped(server.accessToken))" provides="server"\(productVersionAttribute)>\(connectionsXML)</Device>
        </MediaContainer>
        """

        return xmlResponse(url: url, body: xml)
    }

    private func libraryID(for path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count >= 4,
              components[0] == "library",
              components[1] == "sections",
              components[3] == "all" else {
            return nil
        }

        return String(components[2])
    }

    private func metadataIDs(for path: String) -> Set<String>? {
        let components = path.split(separator: "/")
        guard components.count >= 3,
              components[0] == "library",
              components[1] == "metadata" else {
            return nil
        }

        return Set(components[2].split(separator: ",").map(String.init))
    }

    private func streamID(forLevelsPath path: String) -> Int? {
        let components = path.split(separator: "/")
        guard components.count == 4,
              components[0] == "library",
              components[1] == "streams",
              components[3] == "levels" else {
            return nil
        }

        return Int(components[2])
    }

    private func jsonResponse(url: URL, object: [String: Any], headers: [String: String] = [:]) -> PlexDebugMockResponse? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headers.merging(["Content-Type": "application/json"]) { current, _ in current }
        )!
        return PlexDebugMockResponse(response: response, data: data)
    }

    private func xmlResponse(url: URL, body: String) -> PlexDebugMockResponse {
        let data = Data(body.utf8)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/xml"]
        )!
        return PlexDebugMockResponse(response: response, data: data)
    }

    private func sessionObject(from session: PlexSession, payload: PlexMockServerPayload.ActiveSession?) -> [String: Any] {
        var object = compactObject([
            "sessionKey": session.sessionKey,
            "ratingKey": session.ratingKey,
            "key": session.key,
            "type": session.type,
            "title": session.title,
            "grandparentTitle": session.grandparentTitle,
            "parentTitle": session.parentTitle,
            "parentIndex": session.parentIndex,
            "index": session.index,
            "thumb": session.thumb,
            "parentThumb": session.parentThumb,
            "grandparentThumb": session.grandparentThumb,
            "art": session.art,
            "duration": session.duration,
            "viewOffset": session.viewOffset,
            "year": session.year,
            "User": compactObject([
                "id": session.user?.id,
                "thumb": session.user?.thumb,
                "title": session.user?.title,
            ]),
            "Player": compactObject([
                "address": session.player.address,
                "machineIdentifier": session.player.machineIdentifier,
                "platform": session.player.platform,
                "product": session.player.product,
                "remotePublicAddress": session.player.remotePublicAddress,
                "state": session.player.state,
                "title": session.player.title,
                "local": session.player.local,
                "relayed": session.player.relayed,
                "secure": session.player.secure,
            ]),
            "Session": compactObject([
                "id": session.session?.id,
                "bandwidth": session.session?.bandwidth,
                "location": session.session?.location,
            ]),
        ])

        if let transcodeSession = payload?.transcodeSession {
            object["TranscodeSession"] = transcodeSessionObject(from: transcodeSession)
        } else if let transcodeSession = session.transcodeSession {
            object["TranscodeSession"] = compactObject(["key": transcodeSession.key])
        }

        if let media = payload?.media {
            object["Media"] = media.map(mediaObject(from:))
        } else if let media = session.media {
            object["Media"] = media.map { media in
                mediaObject(from: media)
            }
        }

        return object
    }

    private func mediaObject(from media: PlexMockServerPayload.Media) -> [String: Any] {
        var object = compactObject([
            "id": media.id,
            "bitrate": media.bitrate,
            "videoCodec": media.videoCodec,
            "audioCodec": media.audioCodec,
            "audioProfile": media.audioProfile,
            "container": media.container,
            "duration": media.duration,
            "width": media.width,
            "height": media.height,
            "audioChannels": media.audioChannels,
            "videoResolution": media.videoResolution,
            "videoFrameRate": media.videoFrameRate,
            "videoProfile": media.videoProfile,
            "has64bitOffsets": media.has64bitOffsets,
            "hasVoiceActivity": media.hasVoiceActivity,
            "optimizedForStreaming": media.optimizedForStreaming,
            "selected": media.selected,
        ])
        object["Part"] = (media.part ?? []).map(partObject(from:))
        return object
    }

    private func mediaObject(from media: PlexMedia) -> [String: Any] {
        var object = compactObject([
            "bitrate": media.bitrate,
            "videoCodec": media.videoCodec,
            "audioCodec": media.audioCodec,
            "container": media.container,
            "width": media.width,
            "height": media.height,
        ])
        object["Part"] = (media.part ?? []).map(partObject(from:))
        return object
    }

    private func partObject(from part: PlexMockServerPayload.Part) -> [String: Any] {
        var object = compactObject([
            "id": part.id,
            "decision": part.decision,
            "bitrate": part.bitrate,
            "videoCodec": part.videoCodec,
            "audioCodec": part.audioCodec,
            "container": part.container,
            "duration": part.duration,
            "file": part.file,
            "key": part.key,
            "size": part.size,
            "width": part.width,
            "height": part.height,
            "videoProfile": part.videoProfile,
            "has64bitOffsets": part.has64bitOffsets,
            "optimizedForStreaming": part.optimizedForStreaming,
            "selected": part.selected,
        ])
        object["Stream"] = (part.stream ?? []).map(streamObject(from:))
        return object
    }

    private func partObject(from part: PlexPart) -> [String: Any] {
        var object = compactObject([
            "decision": part.decision,
            "bitrate": part.bitrate,
            "videoCodec": part.videoCodec,
            "audioCodec": part.audioCodec,
            "container": part.container,
            "width": part.width,
            "height": part.height,
        ])
        object["Stream"] = (part.stream ?? []).map(streamObject(from:))
        return object
    }

    private func streamObject(from stream: PlexMockServerPayload.Stream) -> [String: Any] {
        compactObject([
            "id": stream.id,
            "streamType": stream.streamType,
            "codec": stream.codec,
            "profile": stream.profile,
            "bitrate": stream.bitrate,
            "width": stream.width,
            "height": stream.height,
            "displayTitle": stream.displayTitle,
            "extendedDisplayTitle": stream.extendedDisplayTitle,
            "decision": stream.decision,
            "location": stream.location,
            "channels": stream.channels,
            "audioChannelLayout": stream.audioChannelLayout,
            "samplingRate": stream.samplingRate,
            "default": stream.default,
            "language": stream.language,
            "title": stream.title,
            "selected": stream.selected,
        ])
    }

    private func streamObject(from stream: PlexStream) -> [String: Any] {
        compactObject([
            "id": stream.id,
            "streamType": stream.streamType,
            "codec": stream.codec,
            "bitrate": stream.bitrate,
            "width": stream.width,
            "height": stream.height,
            "selected": stream.selected,
        ])
    }

    private func transcodeSessionObject(from transcodeSession: PlexMockServerPayload.TranscodeSession) -> [String: Any] {
        compactObject([
            "key": transcodeSession.key,
            "videoDecision": transcodeSession.videoDecision,
            "audioDecision": transcodeSession.audioDecision,
            "protocol": transcodeSession.protocolName,
            "container": transcodeSession.container,
            "videoCodec": transcodeSession.videoCodec,
            "audioCodec": transcodeSession.audioCodec,
            "sourceVideoCodec": transcodeSession.sourceVideoCodec,
            "sourceAudioCodec": transcodeSession.sourceAudioCodec,
            "width": transcodeSession.width,
            "height": transcodeSession.height,
            "progress": transcodeSession.progress,
            "speed": transcodeSession.speed,
            "throttled": transcodeSession.throttled,
            "transcodeHwRequested": transcodeSession.transcodeHwRequested,
            "transcodeHwFullPipeline": transcodeSession.transcodeHwFullPipeline,
        ])
    }

    private func historyItemObject(from item: PlexHistoryItem) -> [String: Any] {
        compactObject([
            "historyKey": item.historyKey,
            "key": item.key,
            "ratingKey": item.ratingKey,
            "title": item.title,
            "type": item.type,
            "thumb": item.thumb,
            "parentThumb": item.parentThumb,
            "grandparentThumb": item.grandparentThumb,
            "art": item.art,
            "grandparentTitle": item.grandparentTitle,
            "parentTitle": item.parentTitle,
            "parentIndex": item.parentIndex,
            "index": item.index,
            "originallyAvailableAt": item.originallyAvailableAt,
            "viewedAt": item.viewedAt.map { Int($0.timeIntervalSince1970) },
            "accountID": item.accountID,
            "deviceID": item.deviceID,
        ])
    }

    private func accountObject(from account: PlexAccount) -> [String: Any] {
        compactObject([
            "id": account.id,
            "name": account.name,
            "thumb": account.thumb,
        ])
    }

    private func metadataItemObject(from item: PlexMetadataItem) -> [String: Any] {
        compactObject([
            "ratingKey": item.ratingKey,
            "grandparentRatingKey": item.grandparentRatingKey,
            "grandparentTitle": item.grandparentTitle,
            "grandparentThumb": item.grandparentThumb,
        ])
    }

    private func libraryDirectoryObject(from section: PlexDebugMockLibrarySection) -> [String: Any] {
        let library = section.library
        return compactObject([
            "key": library.id,
            "title": library.title,
            "type": section.rawType,
            "composite": library.compositePath,
            "art": library.artPath,
            "thumb": library.thumbPath,
            "updatedAt": library.updatedAt.map { Int($0.timeIntervalSince1970) },
            "scannedAt": library.scannedAt.map { Int($0.timeIntervalSince1970) },
            "contentChangedAt": library.contentChangedAt.map { Int($0.timeIntervalSince1970) },
            "content": true,
            "directory": true,
        ])
    }

    private func libraryRecentItemObject(from item: PlexDebugMockLibraryItem) -> [String: Any] {
        compactObject([
            "ratingKey": item.ratingKey,
            "title": item.title,
            "addedAt": item.addedAt.map { Int($0.timeIntervalSince1970) },
            "art": item.art,
            "thumb": item.thumb,
        ])
    }

    private func compactObject(_ values: [String: Any?]) -> [String: Any] {
        values.compactMapValues { $0 }
    }

    private func xmlEscaped<S: StringProtocol>(_ value: S) -> String {
        String(value)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func materializeSession(
        _ session: PlexMockServerPayload.ActiveSession,
        usersByID: [Int: PlexMockServerPayload.User],
        moviesByID: [String: PlexMockServerPayload.Movie],
        showsByID: [String: PlexMockServerPayload.Show],
        episodesByID: [String: PlexMockServerPayload.Episode],
        audiobooksByID: [String: PlexMockServerPayload.Audiobook]
    ) -> PlexSession {
        let user = resolvedUser(for: session.userID, usersByID: usersByID)
        let media = resolvedMedia(
            type: session.mediaType,
            id: session.mediaID,
            moviesByID: moviesByID,
            showsByID: showsByID,
            episodesByID: episodesByID,
            audiobooksByID: audiobooksByID
        )
        let mediaParts: [PlexMedia]?
        if let mockMedia = session.media {
            mediaParts = mockMedia.map(materializeMedia(_:))
        } else if session.mediaDecision != nil || session.audioStream != nil {
            let stream = session.audioStream.map {
                PlexStream(
                    id: $0.id,
                    streamType: $0.streamType,
                    codec: $0.codec,
                    selected: $0.selected
                )
            }
            mediaParts = [PlexMedia(part: [PlexPart(
                decision: session.mediaDecision,
                stream: stream.map { [$0] }
            )])]
        } else {
            mediaParts = nil
        }

        return PlexSession(
            sessionKey: session.sessionKey,
            ratingKey: media.id,
            key: "/library/metadata/\(media.id)",
            type: media.type,
            subtype: nil,
            live: false,
            title: media.title,
            grandparentTitle: media.grandparentTitle,
            parentTitle: media.parentTitle,
            parentIndex: media.parentIndex,
            index: media.index,
            thumb: media.thumb,
            parentThumb: media.parentThumb,
            grandparentThumb: media.grandparentThumb,
            art: media.art,
            duration: session.duration,
            viewOffset: session.viewOffset,
            year: media.year,
            user: user,
            player: session.player.materialize(),
            session: session.session?.materialize(),
            transcodeSession: session.transcodeSession?.materialize(),
            media: mediaParts
        )
    }

    private static func materializeMedia(_ media: PlexMockServerPayload.Media) -> PlexMedia {
        PlexMedia(
            bitrate: media.bitrate,
            videoCodec: media.videoCodec,
            audioCodec: media.audioCodec,
            container: media.container,
            width: media.width,
            height: media.height,
            part: media.part?.map(materializePart(_:))
        )
    }

    private static func materializePart(_ part: PlexMockServerPayload.Part) -> PlexPart {
        PlexPart(
            decision: part.decision,
            bitrate: part.bitrate,
            videoCodec: part.videoCodec,
            audioCodec: part.audioCodec,
            container: part.container,
            width: part.width,
            height: part.height,
            stream: part.stream?.map(materializeStream(_:))
        )
    }

    private static func materializeStream(_ stream: PlexMockServerPayload.Stream) -> PlexStream {
        PlexStream(
            id: stream.id,
            streamType: stream.streamType,
            codec: stream.codec,
            bitrate: stream.bitrate,
            width: stream.width,
            height: stream.height,
            displayTitle: stream.displayTitle,
            extendedDisplayTitle: stream.extendedDisplayTitle,
            channels: stream.channels,
            language: stream.language,
            title: stream.title,
            selected: stream.selected
        )
    }

    private static func materializeHistoryItem(
        _ event: PlexMockServerPayload.HistoryEvent,
        referenceDate: Date,
        moviesByID: [String: PlexMockServerPayload.Movie],
        showsByID: [String: PlexMockServerPayload.Show],
        episodesByID: [String: PlexMockServerPayload.Episode]
    ) -> PlexHistoryItem {
        let media = resolvedMedia(
            type: event.mediaType,
            id: event.mediaID,
            moviesByID: moviesByID,
            showsByID: showsByID,
            episodesByID: episodesByID,
            audiobooksByID: [:]
        )

        return PlexHistoryItem(
            historyKey: event.historyKey,
            key: "/library/metadata/\(media.id)",
            ratingKey: media.id,
            title: media.title,
            type: media.type,
            thumb: media.thumb,
            parentThumb: media.parentThumb,
            grandparentThumb: media.grandparentThumb,
            art: media.art,
            grandparentTitle: media.grandparentTitle,
            parentTitle: media.parentTitle,
            parentIndex: media.parentIndex,
            index: media.index,
            originallyAvailableAt: media.originallyAvailableAt,
            viewedAt: referenceDate.addingTimeInterval(-TimeInterval(event.viewedAtSecondsAgo)),
            accountID: event.userID,
            deviceID: event.deviceID
        )
    }

    private static func materializeMetadataItem(
        _ episode: PlexMockServerPayload.Episode,
        showsByID: [String: PlexMockServerPayload.Show]
    ) -> PlexMetadataItem {
        guard let show = showsByID[episode.showID] else {
            preconditionFailure("Missing mock show \(episode.showID) for episode \(episode.id)")
        }

        return PlexMetadataItem(
            ratingKey: episode.id,
            grandparentRatingKey: show.id,
            grandparentTitle: show.title,
            grandparentThumb: show.poster
        )
    }

    private static func materializeLibrarySection(
        _ library: PlexMockServerPayload.Library,
        referenceDate: Date,
        moviesByID: [String: PlexMockServerPayload.Movie],
        showsByID: [String: PlexMockServerPayload.Show],
        audiobooksByID: [String: PlexMockServerPayload.Audiobook]
    ) -> PlexDebugMockLibrarySection {
        let recentItems: [PlexDebugMockLibraryItem]
        if library.type == "artist" {
            var latestEntryByArtist: [String: (entry: PlexMockServerPayload.LibraryEntry, audiobook: PlexMockServerPayload.Audiobook)] = [:]
            var artistOrder: [String] = []

            for entry in library.entries.sorted(by: { $0.addedAtSecondsAgo < $1.addedAtSecondsAgo }) {
                guard let audiobook = audiobooksByID[entry.mediaID],
                      let artistTitle = audiobook.artistTitle?.nilIfBlank else {
                    continue
                }

                if latestEntryByArtist[artistTitle] == nil {
                    artistOrder.append(artistTitle)
                    latestEntryByArtist[artistTitle] = (entry, audiobook)
                }
            }

            recentItems = artistOrder.compactMap { artistTitle -> PlexDebugMockLibraryItem? in
                guard let resolved = latestEntryByArtist[artistTitle] else {
                    return nil
                }

                return PlexDebugMockLibraryItem(
                    ratingKey: resolved.audiobook.id,
                    title: artistTitle,
                    addedAt: referenceDate.addingTimeInterval(-TimeInterval(resolved.entry.addedAtSecondsAgo)),
                    art: resolved.audiobook.art ?? resolved.audiobook.cover,
                    thumb: resolved.audiobook.cover
                )
            }
        } else {
            recentItems = library.entries
                .sorted { $0.addedAtSecondsAgo < $1.addedAtSecondsAgo }
                .map {
                    resolvedLibraryItem(
                        type: library.type,
                        id: $0.mediaID,
                        moviesByID: moviesByID,
                        showsByID: showsByID,
                        audiobooksByID: audiobooksByID
                    ).recentItem(addedAt: referenceDate.addingTimeInterval(-TimeInterval($0.addedAtSecondsAgo)))
                }
        }

        let latestItem = recentItems.first
        let secondarySummary = library.secondarySummary

        return PlexDebugMockLibrarySection(
            library: PlexLibrary(
                id: library.id,
                title: library.title,
                type: PlexLibraryType(rawValue: library.type),
                compositePath: latestItem?.thumb,
                artPath: latestItem?.art,
                thumbPath: latestItem?.thumb,
                itemCount: recentItems.count,
                secondaryCount: secondarySummary?.count,
                secondaryCountLabel: secondarySummary?.label,
                updatedAt: library.updatedAtSecondsAgo.map { referenceDate.addingTimeInterval(-TimeInterval($0)) },
                scannedAt: library.scannedAtSecondsAgo.map { referenceDate.addingTimeInterval(-TimeInterval($0)) },
                contentChangedAt: library.contentChangedAtSecondsAgo.map { referenceDate.addingTimeInterval(-TimeInterval($0)) },
                latestAddedAt: latestItem?.addedAt,
                latestItemTitle: latestItem?.title
            ),
            rawType: library.type,
            recentItems: recentItems,
            countOverrides: secondarySummary.map { [$0.queryType: $0.count] } ?? [:]
        )
    }

    private static func resolvedUser(
        for userID: Int,
        usersByID: [Int: PlexMockServerPayload.User]
    ) -> PlexUser {
        guard let user = usersByID[userID] else {
            preconditionFailure("Missing mock user \(userID)")
        }

        return user.materializeUser()
    }

    private static func resolvedMedia(
        type: String,
        id: String,
        moviesByID: [String: PlexMockServerPayload.Movie],
        showsByID: [String: PlexMockServerPayload.Show],
        episodesByID: [String: PlexMockServerPayload.Episode],
        audiobooksByID: [String: PlexMockServerPayload.Audiobook]
    ) -> PlexDebugResolvedMedia {
        switch type {
        case "movie":
            guard let movie = moviesByID[id] else {
                preconditionFailure("Missing mock movie \(id)")
            }

            return PlexDebugResolvedMedia(
                id: movie.id,
                type: "movie",
                title: movie.title,
                year: movie.year,
                thumb: movie.poster,
                parentThumb: nil,
                grandparentThumb: nil,
                art: movie.art,
                grandparentTitle: nil,
                parentTitle: nil,
                parentIndex: nil,
                index: nil,
                originallyAvailableAt: movie.originallyAvailableAt
            )
        case "episode":
            guard let episode = episodesByID[id] else {
                preconditionFailure("Missing mock episode \(id)")
            }
            guard let show = showsByID[episode.showID] else {
                preconditionFailure("Missing mock show \(episode.showID) for episode \(id)")
            }

            return PlexDebugResolvedMedia(
                id: episode.id,
                type: "episode",
                title: episode.title,
                year: nil,
                thumb: nil,
                parentThumb: nil,
                grandparentThumb: show.poster,
                art: show.art,
                grandparentTitle: show.title,
                parentTitle: "Season \(episode.seasonNumber)",
                parentIndex: episode.seasonNumber,
                index: episode.episodeNumber,
                originallyAvailableAt: episode.originallyAvailableAt
            )
        case "audiobook":
            guard let audiobook = audiobooksByID[id] else {
                preconditionFailure("Missing mock audiobook \(id)")
            }

            return PlexDebugResolvedMedia(
                id: audiobook.id,
                type: "track",
                title: audiobook.trackTitle ?? audiobook.title,
                year: audiobook.year,
                thumb: audiobook.cover,
                parentThumb: audiobook.cover,
                grandparentThumb: nil,
                art: audiobook.art,
                grandparentTitle: audiobook.artistTitle,
                parentTitle: audiobook.albumTitle ?? audiobook.title,
                parentIndex: nil,
                index: nil,
                originallyAvailableAt: nil
            )
        default:
            preconditionFailure("Unsupported mock media type \(type)")
        }
    }

    private static func resolvedLibraryItem(
        type: String,
        id: String,
        moviesByID: [String: PlexMockServerPayload.Movie],
        showsByID: [String: PlexMockServerPayload.Show],
        audiobooksByID: [String: PlexMockServerPayload.Audiobook]
    ) -> PlexDebugResolvedLibraryItem {
        switch type {
        case "movie":
            guard let movie = moviesByID[id] else {
                preconditionFailure("Missing mock movie \(id)")
            }

            return PlexDebugResolvedLibraryItem(
                ratingKey: movie.id,
                title: movie.title,
                thumb: movie.poster,
                art: movie.art
            )
        case "show":
            guard let show = showsByID[id] else {
                preconditionFailure("Missing mock show \(id)")
            }

            return PlexDebugResolvedLibraryItem(
                ratingKey: show.id,
                title: show.title,
                thumb: show.poster,
                art: show.art
            )
        case "audiobook", "artist":
            guard let audiobook = audiobooksByID[id] else {
                preconditionFailure("Missing mock audiobook \(id)")
            }

            return PlexDebugResolvedLibraryItem(
                ratingKey: audiobook.id,
                title: audiobook.title,
                thumb: audiobook.cover,
                art: audiobook.art ?? audiobook.cover
            )
        default:
            preconditionFailure("Unsupported mock library type \(type)")
        }
    }
}

private struct DebugSeededArtwork {
    let url: URL
    let data: Data
    let image: NSImage

    static func load(
        serverURL: URL,
        mockPath: String,
        sourceFileName: String,
        resourceDirectory: String = "Resources/MockServer/avatars"
    ) -> DebugSeededArtwork {
        let mockServerPrefix = "Resources/MockServer/"
        let relativeDirectory = resourceDirectory.replacingOccurrences(of: mockServerPrefix, with: "")
        let sourceURL = PlexMockServerResourceLocator.url(for: "\(relativeDirectory)/\(sourceFileName)")

        let data = try! Data(contentsOf: sourceURL)
        guard let image = NSImage(contentsOf: sourceURL) else {
            preconditionFailure("Missing mock avatar image at \(sourceURL.path)")
        }

        return DebugSeededArtwork(
            url: PlexURLBuilder.mediaURL(serverURL: serverURL, path: mockPath)!,
            data: data,
            image: image
        )
    }
}

private struct PlexDebugMockLibrarySection {
    let library: PlexLibrary
    let rawType: String
    let recentItems: [PlexDebugMockLibraryItem]
    let countOverrides: [Int: Int]
}

private struct PlexDebugMockLibraryItem {
    let ratingKey: String
    let title: String
    let addedAt: Date?
    let art: String?
    let thumb: String?
}

private struct PlexDebugResolvedMedia {
    let id: String
    let type: String
    let title: String
    let year: Int?
    let thumb: String?
    let parentThumb: String?
    let grandparentThumb: String?
    let art: String?
    let grandparentTitle: String?
    let parentTitle: String?
    let parentIndex: Int?
    let index: Int?
    let originallyAvailableAt: String?
}

private struct PlexDebugResolvedLibraryItem {
    let ratingKey: String
    let title: String
    let thumb: String?
    let art: String?

    func recentItem(addedAt: Date) -> PlexDebugMockLibraryItem {
        PlexDebugMockLibraryItem(
            ratingKey: ratingKey,
            title: title,
            addedAt: addedAt,
            art: art,
            thumb: thumb
        )
    }
}

private final class PlexDebugMockState: @unchecked Sendable {
    private let lock = NSLock()
    private var terminatedSessionIDs: Set<String> = []

    func terminateSession(withID sessionID: String) {
        guard let sessionID = sessionID.nilIfBlank else {
            return
        }

        _ = lock.withLock {
            terminatedSessionIDs.insert(sessionID)
        }
    }

    func isTerminated(_ session: PlexSession) -> Bool {
        guard let serverSessionID = session.serverSessionID else {
            return false
        }

        return lock.withLock {
            terminatedSessionIDs.contains(serverSessionID)
        }
    }
}

private final class PlexDebugMockStateRegistry: @unchecked Sendable {
    static let shared = PlexDebugMockStateRegistry()
    static let headerName = "X-PlexBar-Mock-State-ID"

    private let lock = NSLock()
    private var states: [String: PlexDebugMockState] = [:]

    private init() {}

    func register(_ state: PlexDebugMockState) -> String {
        let id = UUID().uuidString

        lock.withLock {
            states[id] = state
        }

        return id
    }

    func state(for request: URLRequest) -> PlexDebugMockState? {
        guard let id = request.value(forHTTPHeaderField: Self.headerName) else {
            return nil
        }

        return lock.withLock {
            states[id]
        }
    }
}

private final class PlexDebugMockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let forwardingSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: configuration)
    }()

    private var forwardingTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let state = PlexDebugMockStateRegistry.shared.state(for: request),
           let response = debugFixture.response(for: request, state: state) {
            client?.urlProtocol(self, didReceive: response.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        forwardingTask = Self.forwardingSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                return
            }

            if let error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }

            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }

            if let data {
                client?.urlProtocol(self, didLoad: data)
            }

            client?.urlProtocolDidFinishLoading(self)
        }
        forwardingTask?.resume()
    }

    override func stopLoading() {
        forwardingTask?.cancel()
        forwardingTask = nil
    }
}

private struct PlexDebugMockResponse {
    let response: HTTPURLResponse
    let data: Data
}

#endif
