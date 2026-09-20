import PlexClientKit
import PlexModels
import PlexMockData
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
    let streamLevelsByID: [Int: [Double]]
    let resolvedLocationsByIPAddress: [String: String]
    let historyItems: [PlexHistoryItem]
    let catalog: PlexMockMediaCatalog
    let accountsByID: [Int: PlexAccount]
    let historyDevices: [PlexHistoryDevice]
    let librarySections: [PlexDebugMockLibrarySection]
    let snapshotDate: Date
    let artwork: [DebugMockArtwork]

    var libraries: [PlexLibrary] {
        librarySections.map(\.library)
    }

    static func makeDefault() -> PlexDebugMockFixture {
        let payload = try! PlexMockServerPayload.loadDefault()
        let snapshotDate = Date()
        let userToken = "eyJhbGciOiJFZERTQSIsImtpZCI6Im1vY2siLCJ0eXAiOiJKV1QifQ."
            + "eyJleHAiOjQxMDI0NDQ4MDAsInVzZXJuYW1lIjoibW9jayIsImVtYWlsIjoibW9ja0BleGFtcGxlLmNvbSIs"
            + "ImZyaWVuZGx5X25hbWUiOiJNb2NrIn0.mock-signature"
        let server = payload.server.materialize()
        let serverURL = server.connections[0].uri
        let usersByID = Dictionary(uniqueKeysWithValues: payload.users.map { ($0.id, $0) })
        let catalog = try! PlexMockMediaCatalog.loadDefault()
        precondition(payload.libraries.allSatisfy { library in
            library.entries.allSatisfy { catalog.record(for: $0.mediaID)?.item.type == library.type }
        }, "Every mock library root must resolve to the declared media type")

        let activeConnection = PlexResolvedConnection(
            serverID: server.id,
            url: serverURL,
            kind: .local,
            validatedAt: snapshotDate
        )
        guard let authenticatedProfile = usersByID[payload.authenticatedUserID] else {
            preconditionFailure("Missing authenticated mock user")
        }
        let avatarResource = payload.artwork.first { $0.path == authenticatedProfile.avatar }
        let authenticatedUser = authenticatedProfile.materializeAuthenticatedUser(
            thumbOverride: avatarResource.map { PlexMockServerResourceLocator.url(for: $0.resource).absoluteString }
        )
        let devices = payload.users.flatMap(\.devices)
        let locationsByIP = devices.reduce(into: [String: String]()) { locations, device in
            if let ip = device.connection.remotePublicAddress, let location = device.connection.resolvedLocation {
                locations[ip] = location
            }
        }

        let accountsByID = Dictionary(
            uniqueKeysWithValues: payload.users.map { userPayload in
                let account = userPayload.materialize()
                return (account.id, account)
            }
        )
        let sessions = payload.activeSessions.map {
            materializeSession($0, usersByID: usersByID, catalog: catalog)
        }
        let historyItems = payload.historyEvents.map {
            materializeHistoryItem($0, referenceDate: snapshotDate, catalog: catalog)
        }
        let librarySections = payload.libraries.map {
            materializeLibrarySection($0, referenceDate: snapshotDate, catalog: catalog)
        }

        return PlexDebugMockFixture(
            userToken: userToken,
            authenticatedUser: authenticatedUser,
            server: server,
            activeConnection: activeConnection,
            sessions: sessions,
            streamLevelsByID: Dictionary(
                payload.activeSessions.compactMap { session in
                    session.audioStream.map { ($0.id, $0.levels) }
                },
                uniquingKeysWith: { existing, _ in existing }
            ),
            resolvedLocationsByIPAddress: locationsByIP,
            historyItems: historyItems,
            catalog: catalog,
            accountsByID: accountsByID,
            historyDevices: devices.map { $0.materializeHistoryDevice() }.sorted { $0.id < $1.id },
            librarySections: librarySections,
            snapshotDate: snapshotDate,
            artwork: payload.artwork.map {
                DebugMockArtwork.load(serverURL: serverURL, mockPath: $0.path, resource: $0.resource)
            }
        )
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

        let method = request.httpMethod ?? "GET"
        let isTermination = url.path == "/status/sessions/terminate" && method == "POST"
        guard (method == "GET" && url.path != "/status/sessions/terminate") || isTermination else {
            return errorResponse(for: request, status: 405)
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
                        "Metadata": filteredSessions.map { sessionObject(from: $0) }
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
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let id = query.first { $0.name == "metadataItemID" }?.value
            let cutoff = query.first { $0.name == "viewedAt>" }?.value.flatMap(Double.init)
            let items = historyItems.compactMap { history -> (item: PlexHistoryItem, date: Date)? in
                guard let viewedAt = history.viewedAt else { return nil }
                let media = history.ratingKey.flatMap { catalog.record(for: $0)?.item }
                let matchesID = id.map {
                    [media?.ratingKey, media?.parentRatingKey, media?.grandparentRatingKey].contains($0)
                } ?? true
                let matchesDate = cutoff.map { viewedAt.timeIntervalSince1970 > $0 } ?? true
                return matchesID && matchesDate ? (history, viewedAt) : nil
            }.sorted { $0.date > $1.date }
            return pagedMetadataResponse(
                for: request,
                metadata: items.map { historyItemObject(from: $0.item) }
            )
        }

        if let response = catalogResponse(for: request) {
            return response
        }

        if url.path == "/statistics/media" {
            let accounts = accountsByID.keys.sorted().compactMap { accountsByID[$0] }.map { accountObject(from: $0) }
            return jsonResponse(
                url: url,
                object: [
                    "MediaContainer": [
                        "Account": accounts,
                        "Device": historyDevices.map { device in
                            compactObject(["id": device.id, "name": device.name, "platform": device.platform])
                        }
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

        if url.path == "/media/providers" {
            return jsonResponse(
                url: url,
                object: [
                    "MediaContainer": [
                        "MediaProvider": [[
                            "identifier": "com.plexapp.plugins.library",
                            "Feature": [
                                [
                                    "type": "content",
                                    "key": "/library/sections",
                                    "Directory": librarySections.compactMap {
                                        libraryProviderDirectoryObject(from: $0)
                                    },
                                ],
                                ["type": "promoted", "key": "/hubs/promoted"],
                                ["type": "continuewatching", "key": "/hubs/continueWatching"],
                                ["type": "search", "key": "/hubs/search"],
                                ["type": "playlist", "key": "/playlists", "readOnly": true],
                            ],
                        ]]
                    ]
                ]
            )
        }

        if url.path == "/hubs/promoted" {
            let count = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "count" })?
                .value
                .flatMap(Int.init) ?? 20
            let hubs = promotedHubObjects(itemLimit: max(count, 1))
            return jsonResponse(
                url: url,
                object: [
                    "MediaContainer": [
                        "size": hubs.count,
                        "Hub": hubs
                    ]
                ]
            )
        }

        if url.path == "/hubs/home/recentlyAdded",
           let librarySection = homeHubLibrarySection(for: url) {
            return pagedMetadataResponse(
                for: request,
                metadata: librarySection.recentItems.map {
                    browseItemObject(from: $0, in: librarySection)
                }
            )
        }

        if let libraryID = collectionsLibraryID(for: url.path),
           let librarySection = librarySections.first(where: { $0.library.id == libraryID }),
           let collectionID = mockCollectionID(for: libraryID) {
            return pagedMetadataResponse(
                for: request,
                metadata: [collectionObject(from: librarySection, collectionID: collectionID)]
            )
        }

        if let collectionID = collectionItemsID(for: url.path),
           let librarySection = librarySection(forMockCollectionID: collectionID) {
            return pagedMetadataResponse(
                for: request,
                metadata: librarySection.recentItems.map {
                    browseItemObject(from: $0, in: librarySection)
                }
            )
        }

        if url.path == "/playlists" {
            return pagedMetadataResponse(for: request, metadata: playlistObjects())
        }

        if let playlistID = playlistItemsID(for: url.path),
           let librarySection = librarySection(forMockPlaylistID: playlistID) {
            return pagedMetadataResponse(
                for: request,
                metadata: playlistRecords(in: librarySection).enumerated().map { index, item in
                    var object = browseItemObject(from: item, in: librarySection)
                    object["playlistItemID"] = "\(playlistID)-\(index + 1)"
                    return object
                }
            )
        }

        if let libraryID = libraryDescriptorID(for: url.path, descriptor: "filters"),
           let librarySection = librarySections.first(where: { $0.library.id == libraryID }) {
            return jsonResponse(
                url: url,
                object: libraryFiltersObject(from: librarySection)
            )
        }

        if let libraryID = libraryDescriptorID(for: url.path, descriptor: "sorts"),
           let librarySection = librarySections.first(where: { $0.library.id == libraryID }) {
            return jsonResponse(
                url: url,
                object: librarySortsObject(from: librarySection)
            )
        }

        if let libraryID = libraryDetailsID(for: url.path),
           let librarySection = librarySections.first(where: { $0.library.id == libraryID }) {
            return jsonResponse(
                url: url,
                object: libraryBrowseDefinitionObject(from: librarySection)
            )
        }

        if let libraryID = libraryID(for: url.path),
           let section = librarySections.first(where: { $0.library.id == libraryID }) {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let requestedType = query.first { $0.name == "type" }?.value.flatMap(Int.init)
            let typeNames = [1: "movie", 2: "show", 3: "season", 4: "episode", 8: "artist", 9: "album", 10: "track"]
            let type = requestedType.flatMap { typeNames[$0] } ?? section.rawType
            let title = query.first { $0.name == "title" }?.value?.nilIfBlank
            let unwatched = query.contains { $0.name == "unwatched" && $0.value == "1" }
            let inProgress = query.contains { $0.name == "inProgress" && $0.value == "1" }
            let records = catalog.records.filter { record in
                let item = record.item
                return item.librarySectionID == libraryID && item.type == type
                    && (title.map { item.title.localizedStandardContains($0) } ?? true)
                    && (!unwatched || !item.isWatched)
                    && (!inProgress || hasProgress(record))
            }
            let sorted = sortedLibraryItems(records, sort: query.first { $0.name == "sort" }?.value)
            return pagedMetadataResponse(for: request, metadata: sorted.map { $0.object(referenceDate: snapshotDate) })
        }

        return nil
    }

    func errorResponse(for request: URLRequest, status: Int) -> PlexDebugMockResponse {
        let url = request.url!
        let message = "Mock data does not support \(request.httpMethod ?? "GET") \(url.path)"
        return PlexDebugMockResponse(
            response: HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "text/plain; charset=utf-8"]
            )!,
            data: Data(message.utf8)
        )
    }

    private func hasProgress(_ record: PlexMockMediaCatalog.Record) -> Bool {
        let items = record.item.hasChildren ? catalog.leaves(of: record.item.ratingKey) : [record]
        return items.contains { ($0.item.viewOffset ?? 0) > 0 && !$0.item.isWatched }
    }

    private func playlistRecords(in section: PlexDebugMockLibrarySection) -> [PlexMockMediaCatalog.Record] {
        section.rawType == "artist"
            ? section.recentItems.flatMap { catalog.leaves(of: $0.item.ratingKey) }
            : section.recentItems
    }

    private func catalogResponse(for request: URLRequest) -> PlexDebugMockResponse? {
        guard let url = request.url else { return nil }
        let components = url.path.split(separator: "/").map(String.init)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let count = max(query.first { $0.name == "count" || $0.name == "limit" }?.value.flatMap(Int.init) ?? 20, 1)

        if let ids = metadataIDs(for: url.path) {
            let objects = ids.sorted().compactMap { id -> [String: Any]? in
                if let record = catalog.record(for: id) {
                    return record.object(referenceDate: snapshotDate)
                }
                if let section = librarySection(forMockCollectionID: id) {
                    return collectionObject(from: section, collectionID: id)
                }
                return playlistObjects().first { $0["ratingKey"] as? String == id }
            }
            guard objects.count == ids.count else { return errorResponse(for: request, status: 404) }
            return pagedMetadataResponse(for: request, metadata: objects)
        }

        if components.count == 4, components[0] == "library", components[1] == "metadata",
           let record = catalog.record(for: components[2]) {
            let records: [PlexMockMediaCatalog.Record]
            switch components[3] {
            case "children": records = catalog.children(of: record.item.ratingKey)
            case "grandchildren", "allLeaves": records = catalog.leaves(of: record.item.ratingKey)
            case "extras": records = record.extraIDs.compactMap { catalog.record(for: $0) }
            default: return nil
            }
            return pagedMetadataResponse(for: request, metadata: records.map { $0.object(referenceDate: snapshotDate) })
        }

        if url.path == "/hubs/continueWatching" || url.path == "/hubs/home/continueWatching" {
            let records = catalog.records.filter {
                ($0.item.type == "movie" || $0.item.type == "episode") && hasProgress($0)
            }
            if url.path == "/hubs/home/continueWatching" {
                return pagedMetadataResponse(for: request, metadata: records.map { $0.object(referenceDate: snapshotDate) })
            }
            return jsonResponse(url: url, object: ["MediaContainer": ["Hub": [hubObject(
                id: "continueWatching", title: "Continue Watching", type: "mixed",
                key: "/hubs/home/continueWatching", records: records, count: count
            )]]])
        }

        if url.path == "/hubs/search" || url.path == "/hubs/search/results" {
            let text = query.first { $0.name == "query" }?.value?.nilIfBlank ?? ""
            let type = query.first { $0.name == "type" }?.value
            let matches = catalog.records.filter { record in
                let item = record.item
                guard !text.isEmpty, !["season", "clip"].contains(item.type ?? "") else { return false }
                return [item.title, item.parentTitle, item.grandparentTitle].compactMap { $0 }
                    .contains { $0.localizedStandardContains(text) }
                    || (item.roles + item.directors + item.writers).contains { $0.tag.localizedStandardContains(text) }
            }
            if url.path == "/hubs/search/results" {
                return pagedMetadataResponse(for: request, metadata: matches.filter { $0.item.type == type }
                    .map { $0.object(referenceDate: snapshotDate) })
            }
            let groups = [("movie", "Movies"), ("show", "TV Shows"), ("episode", "Episodes"),
                          ("artist", "Artists"), ("album", "Albums"), ("track", "Tracks")]
            let hubs = groups.compactMap { type, title -> [String: Any]? in
                let items = matches.filter { $0.item.type == type }
                guard !items.isEmpty else { return nil }
                var path = URLComponents()
                path.path = "/hubs/search/results"
                path.queryItems = [URLQueryItem(name: "query", value: text), URLQueryItem(name: "type", value: type)]
                return hubObject(id: "search.\(type)", title: title, type: type,
                                 key: path.string!, records: items, count: count)
            }
            return jsonResponse(url: url, object: ["MediaContainer": ["Hub": hubs]])
        }

        if components.count == 4 || components.count == 5,
           components[0] == "hubs", components[1] == "metadata", components[3] == "related",
           let record = catalog.record(for: components[2]) {
            let related = record.relatedIDs.compactMap { catalog.record(for: $0) }
            let key = "/hubs/metadata/\(record.item.ratingKey)/related/items"
            if components.count == 5 {
                guard components[4] == "items" else { return nil }
                return pagedMetadataResponse(for: request, metadata: related.map { $0.object(referenceDate: snapshotDate) })
            }
            let hubs = related.isEmpty ? [] : [hubObject(
                id: "related.\(record.item.ratingKey)", title: "More in This Library",
                type: related.first?.item.type ?? "mixed", key: key, records: related, count: count
            )]
            return jsonResponse(url: url, object: ["MediaContainer": ["Hub": hubs]])
        }

        if (components.count == 3 || components.count == 4),
           components[0] == "library", components[1] == "people" {
            let id = components[2]
            let records = catalog.records.filter { record in
                let item = record.item
                return (item.roles + item.directors + item.writers + item.producers).contains { $0.tagKey == id }
            }
            guard let item = records.first?.item,
                  let person = (item.roles + item.directors + item.writers + item.producers).first(where: { $0.tagKey == id }) else {
                return errorResponse(for: request, status: 404)
            }
            if components.count == 4 {
                guard components[3] == "media" else { return nil }
                return pagedMetadataResponse(for: request, metadata: records.map { $0.object(referenceDate: snapshotDate) })
            }
            return jsonResponse(url: url, object: ["MediaContainer": ["Directory": [compactObject([
                "id": person.id, "tag": person.tag, "tagKey": person.tagKey, "thumb": person.thumb
            ])]]])
        }
        return nil
    }

    private func hubObject(
        id: String, title: String, type: String, key: String,
        records: [PlexMockMediaCatalog.Record], count: Int
    ) -> [String: Any] {
        let items = Array(records.prefix(count))
        return ["hubIdentifier": id, "key": key, "title": title, "type": type,
                "size": items.count, "totalSize": records.count, "more": records.count > items.count,
                "Metadata": items.map { $0.object(referenceDate: snapshotDate) }]
    }

    private func remoteResponse(for request: URLRequest) -> PlexDebugMockResponse? {
        guard let url = request.url else {
            return nil
        }

        if let response = remoteAuthenticationResponse(for: url) {
            return response
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

        if url.path == "/api/v2/resources" {
            return serverResourcesResponse(for: url)
        }

        if url.path == "/api/v2/devices" {
            return serverDevicesResponse(for: url)
        }

        if url.path == "/api/v2/geoip" {
            return geoIPResponse(for: url)
        }

        return nil
    }

    private func remoteAuthenticationResponse(for url: URL) -> PlexDebugMockResponse? {
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

        if url.path == "/api/v2/auth/jwk" {
            return jsonResponse(url: url, object: [:])
        }

        if url.path == "/api/v2/auth/nonce" {
            return jsonResponse(url: url, object: ["nonce": "plexbar-mock-nonce"])
        }

        if url.path == "/api/v2/auth/token" {
            return jsonResponse(url: url, object: ["auth_token": userToken])
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

        let location = resolvedLocationsByIPAddress[ipAddress]

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
        guard let artwork = artwork.first(where: { $0.url.path == url.path }) else {
            return nil
        }

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": artwork.contentType])!
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
        jsonResponse(
            url: url,
            object: [
                compactObject([
                    "name": server.name,
                    "clientIdentifier": server.id,
                    "accessToken": server.accessToken,
                    "provides": "server",
                    "productVersion": server.productVersion,
                    "connections": server.connections.map { connection in
                        [
                            "uri": connection.uri.absoluteString,
                            "local": connection.local,
                            "relay": connection.relay
                        ]
                    }
                ])
            ]
        )
    }

    private func serverDevicesResponse(for url: URL) -> PlexDebugMockResponse? {
        jsonResponse(
            url: url,
            object: [
                compactObject([
                    "name": server.name,
                    "clientIdentifier": server.id,
                    "token": server.accessToken,
                    "provides": "server",
                    "connections": server.connections.map { connection in
                        ["uri": connection.uri.absoluteString]
                    }
                ])
            ]
        )
    }

    private func libraryID(for path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count == 4,
              components[0] == "library",
              components[1] == "sections",
              components[3] == "all" else {
            return nil
        }

        return String(components[2])
    }

    private func libraryDetailsID(for path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count == 3,
              components[0] == "library",
              components[1] == "sections" else {
            return nil
        }
        return String(components[2])
    }

    private func collectionsLibraryID(for path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count == 4,
              components[0] == "library",
              components[1] == "sections",
              components[3] == "collections" else {
            return nil
        }
        return String(components[2])
    }

    private func libraryDescriptorID(for path: String, descriptor: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count == 4,
              components[0] == "library",
              components[1] == "sections",
              components[3] == Substring(descriptor) else {
            return nil
        }
        return String(components[2])
    }

    private func collectionItemsID(for path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count == 4,
              components[0] == "library",
              components[1] == "collections",
              components[3] == "items" else {
            return nil
        }
        return String(components[2])
    }

    private func playlistItemsID(for path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count == 3,
              components[0] == "playlists",
              components[2] == "items" else {
            return nil
        }
        return String(components[1])
    }

    private func metadataIDs(for path: String) -> Set<String>? {
        let components = path.split(separator: "/")
        guard components.count == 3,
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

    private func jsonResponse(url: URL, object: Any, headers: [String: String] = [:]) -> PlexDebugMockResponse? {
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

    private func pagedMetadataResponse(
        for request: URLRequest,
        metadata: [[String: Any]]
    ) -> PlexDebugMockResponse? {
        guard let url = request.url else {
            return nil
        }
        let start = max(Int(request.value(forHTTPHeaderField: "X-Plex-Container-Start") ?? "") ?? 0, 0)
        let size = max(Int(request.value(forHTTPHeaderField: "X-Plex-Container-Size") ?? "") ?? metadata.count, 0)
        let page = Array(metadata.dropFirst(start).prefix(size))
        return jsonResponse(
            url: url,
            object: [
                "MediaContainer": [
                    "size": page.count,
                    "totalSize": metadata.count,
                    "offset": start,
                    "Metadata": page
                ]
            ],
            headers: ["X-Plex-Container-Total-Size": String(metadata.count)]
        )
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

    private func sessionObject(from session: PlexSession) -> [String: Any] {
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

        if let transcodeSession = session.transcodeSession {
            object["TranscodeSession"] = compactObject([
                "key": transcodeSession.key,
                "videoDecision": transcodeSession.videoDecision,
                "audioDecision": transcodeSession.audioDecision,
                "sourceVideoCodec": transcodeSession.sourceVideoCodec,
                "sourceAudioCodec": transcodeSession.sourceAudioCodec,
                "videoCodec": transcodeSession.videoCodec,
                "audioCodec": transcodeSession.audioCodec,
                "transcodeHwDecoding": transcodeSession.transcodeHwDecoding,
                "transcodeHwEncoding": transcodeSession.transcodeHwEncoding,
            ])
        }

        if let media = session.media {
            object["Media"] = media.map { media in
                compactObject([
                    "selected": media.selected,
                    "Part": (media.part ?? []).map { part in
                        var partObject = compactObject(["decision": part.decision, "selected": part.selected])

                        if let stream = part.stream {
                            partObject["Stream"] = stream.map { stream in
                                compactObject([
                                    "id": stream.id,
                                    "streamType": stream.streamType,
                                    "codec": stream.codec,
                                    "selected": stream.selected,
                                    "decision": stream.decision,
                                    "displayTitle": stream.displayTitle,
                                    "language": stream.language,
                                    "bitrate": stream.bitrate,
                                ])
                            }
                        }

                        return partObject
                    }
                ])
            }
        }

        return object
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

    private func libraryProviderDirectoryObject(
        from section: PlexDebugMockLibrarySection
    ) -> [String: Any]? {
        guard let metadataTypeID = section.library.type.metadataTypeID else {
            return nil
        }
        return [
            "id": section.library.id,
            "key": "/library/sections/\(section.library.id)",
            "type": section.rawType,
            "title": section.library.title,
            "Pivot": [[
                "id": "library",
                "key": "/library/sections/\(section.library.id)/all?type=\(metadataTypeID)",
                "type": "list",
                "title": "Library",
            ]],
        ]
    }

    private func libraryFiltersObject(
        from section: PlexDebugMockLibrarySection
    ) -> [String: Any] {
        [
            "MediaContainer": [
                "Directory": [
                    [
                        "filter": "unwatched",
                        "filterType": "boolean",
                        "key": "/library/sections/\(section.library.id)/unwatched",
                        "title": "Unwatched",
                    ],
                    [
                        "filter": "inProgress",
                        "filterType": "boolean",
                        "key": "/library/sections/\(section.library.id)/inProgress",
                        "title": "In Progress",
                    ],
                ]
            ]
        ]
    }

    private func librarySortsObject(
        from section: PlexDebugMockLibrarySection
    ) -> [String: Any] {
        [
            "MediaContainer": [
                "Directory": [
                    [
                        "default": "asc",
                        "defaultDirection": "asc",
                        "descKey": "titleSort:desc",
                        "key": "titleSort",
                        "title": "Name",
                    ],
                    [
                        "defaultDirection": "desc",
                        "descKey": "addedAt:desc",
                        "key": "addedAt",
                        "title": "Date Added",
                    ],
                ]
            ]
        ]
    }

    private func libraryBrowseDefinitionObject(
        from section: PlexDebugMockLibrarySection
    ) -> [String: Any] {
        guard let metadataTypeID = section.library.type.metadataTypeID else {
            return ["MediaContainer": ["Directory": [], "Type": []]]
        }
        let browseTypes: [(id: Int, type: String, title: String)] = section.rawType == "artist"
            ? [(8, "artist", "Artists"), (9, "album", "Albums"), (10, "track", "Tracks")]
            : [(metadataTypeID, section.rawType, section.library.title)]
        let filters = (libraryFiltersObject(from: section)["MediaContainer"] as? [String: Any])?["Directory"]
            as? [[String: Any]] ?? []
        let sorts = (librarySortsObject(from: section)["MediaContainer"] as? [String: Any])?["Directory"]
            as? [[String: Any]] ?? []
        return [
            "MediaContainer": [
                "Directory": [["key": "all", "title": "All \(browseTypes[0].title)"]],
                "Type": browseTypes.map { type in
                    [
                        "key": "/library/sections/\(section.library.id)/all?type=\(type.id)",
                        "type": type.type,
                        "title": type.title,
                        "Filter": section.rawType == "artist" ? [] : filters,
                        "Sort": sorts,
                    ] as [String: Any]
                },
            ]
        ]
    }

    private func sortedLibraryItems(
        _ items: [PlexMockMediaCatalog.Record],
        sort: String?
    ) -> [PlexMockMediaCatalog.Record] {
        switch sort {
        case "titleSort:desc":
            items.sorted { $0.item.title.localizedStandardCompare($1.item.title) == .orderedDescending }
        case "addedAt":
            items.sorted { $0.addedAtSecondsAgo > $1.addedAtSecondsAgo }
        case "addedAt:desc":
            items.sorted { $0.addedAtSecondsAgo < $1.addedAtSecondsAgo }
        default:
            items.sorted { $0.item.title.localizedStandardCompare($1.item.title) == .orderedAscending }
        }
    }

    private func browseItemObject(
        from item: PlexMockMediaCatalog.Record,
        in section: PlexDebugMockLibrarySection
    ) -> [String: Any] {
        item.object(referenceDate: snapshotDate)
    }

    private func promotedHubObjects(itemLimit: Int) -> [[String: Any]] {
        librarySections.compactMap { section in
            guard let metadataTypeID = section.library.type.metadataTypeID,
                  !section.recentItems.isEmpty else {
                return nil
            }

            let isAudio = section.rawType == "artist"
            let recentItems = isAudio
                ? sortedLibraryItems(catalog.records.filter {
                    $0.item.librarySectionID == section.library.id && $0.item.type == "album"
                }, sort: "addedAt:desc")
                : section.recentItems
            let items = Array(recentItems.prefix(itemLimit))
            let metadata = items.map { browseItemObject(from: $0, in: section) }
            let hubKey = items
                .map { "/library/metadata/\($0.item.ratingKey)" }
                .joined(separator: ",")
            return [
                "hubIdentifier": isAudio ? "music.recent.added.\(section.library.id)" : "home.\(section.library.id).recent",
                "hubKey": hubKey,
                "key": isAudio
                    ? "/library/sections/\(section.library.id)/all?type=9&sort=addedAt:desc"
                    : "/hubs/home/recentlyAdded?type=\(metadataTypeID)",
                "title": "Recently Added \(section.library.title)",
                "type": isAudio ? "album" : section.rawType,
                "size": metadata.count,
                "totalSize": recentItems.count,
                "more": recentItems.count > metadata.count,
                "style": "shelf",
                "promoted": true,
                "Metadata": metadata
            ]
        }
    }

    private func homeHubLibrarySection(for url: URL) -> PlexDebugMockLibrarySection? {
        let metadataTypeID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "type" })?
            .value
            .flatMap(Int.init)
        return librarySections.first { $0.library.type.metadataTypeID == metadataTypeID }
    }

    private func mockCollectionID(for libraryID: String) -> String? {
        librarySections.firstIndex { $0.library.id == libraryID }
            .map { String(9_101 + $0) }
    }

    private func librarySection(
        forMockCollectionID collectionID: String
    ) -> PlexDebugMockLibrarySection? {
        guard let numericID = Int(collectionID) else {
            return nil
        }
        let index = numericID - 9_101
        guard librarySections.indices.contains(index) else {
            return nil
        }
        return librarySections[index]
    }

    private func collectionObject(
        from section: PlexDebugMockLibrarySection,
        collectionID: String
    ) -> [String: Any] {
        compactObject([
            "ratingKey": collectionID,
            "key": "/library/collections/\(collectionID)/items",
            "type": "collection",
            "title": "\(section.library.title) Collection",
            "composite": section.recentItems.first?.item.thumb,
            "leafCount": section.recentItems.count
        ])
    }

    private func playlistObjects() -> [[String: Any]] {
        let definitions = [
            (id: "9201", type: "video", sectionType: "movie", title: "Video Playlist"),
            (id: "9202", type: "audio", sectionType: "artist", title: "Audio Playlist")
        ]
        return definitions.compactMap { definition in
            guard let section = librarySections.first(where: { $0.rawType == definition.sectionType }) else {
                return nil
            }
            return compactObject([
                "ratingKey": definition.id,
                "key": "/playlists/\(definition.id)/items",
                "type": "playlist",
                "title": definition.title,
                "composite": section.recentItems.first?.item.thumb,
                "leafCount": playlistRecords(in: section).count,
                "readOnly": true,
                "playlistType": definition.type,
                "smart": false
            ])
        }
    }

    private func librarySection(
        forMockPlaylistID playlistID: String
    ) -> PlexDebugMockLibrarySection? {
        let rawType: String
        switch playlistID {
        case "9201":
            rawType = "movie"
        case "9202":
            rawType = "artist"
        default:
            return nil
        }
        return librarySections.first { $0.rawType == rawType }
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
        catalog: PlexMockMediaCatalog
    ) -> PlexSession {
        guard let profile = usersByID[session.userID],
              let device = profile.devices.first(where: { $0.id == session.deviceID }),
              let media = catalog.record(for: session.mediaID)?.item else {
            preconditionFailure("Missing mock session user, device, or media")
        }
        let mediaParts: [PlexMedia]?
        if session.mediaDecision != nil || session.audioStream != nil {
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
                stream: (session.mediaStreams ?? []) + (stream.map { [$0] } ?? [])
            )])]
        } else {
            mediaParts = nil
        }

        return PlexSession(
            sessionKey: session.sessionKey,
            ratingKey: media.ratingKey,
            key: "/library/metadata/\(media.ratingKey)",
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
            duration: media.duration,
            viewOffset: session.viewOffset,
            year: media.year,
            user: profile.materializeUser(),
            player: device.materializePlayer(state: session.state),
            session: session.session?.materialize(location: device.connection.sessionLocation),
            transcodeSession: session.transcodeSession,
            media: mediaParts
        )
    }

    private static func materializeHistoryItem(
        _ event: PlexMockServerPayload.HistoryEvent,
        referenceDate: Date,
        catalog: PlexMockMediaCatalog
    ) -> PlexHistoryItem {
        guard let media = catalog.record(for: event.mediaID)?.item else {
            preconditionFailure("Missing mock history media \(event.mediaID)")
        }

        return PlexHistoryItem(
            historyKey: event.historyKey,
            key: "/library/metadata/\(media.ratingKey)",
            ratingKey: media.ratingKey,
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

    private static func materializeLibrarySection(
        _ library: PlexMockServerPayload.Library,
        referenceDate: Date,
        catalog: PlexMockMediaCatalog
    ) -> PlexDebugMockLibrarySection {
        let recentItems = library.entries.map { catalog.record(for: $0.mediaID)! }
            .sorted { $0.addedAtSecondsAgo < $1.addedAtSecondsAgo }
        let latest = recentItems.first
        let secondaryType: String? = switch library.type {
        case "show": "season"
        case "artist": "album"
        default: nil
        }
        let secondaryCount = secondaryType.map { type in
            catalog.records.filter { $0.item.librarySectionID == library.id && $0.item.type == type }.count
        }
        return PlexDebugMockLibrarySection(
            library: PlexLibrary(
                id: library.id,
                title: library.title,
                type: PlexLibraryType(rawValue: library.type),
                compositePath: latest?.item.thumb,
                artPath: latest?.item.art,
                thumbPath: latest?.item.thumb,
                itemCount: recentItems.count,
                secondaryCount: secondaryCount,
                secondaryCountLabel: secondaryType.map { $0 == "season" ? "seasons" : "albums" },
                updatedAt: library.updatedAtSecondsAgo.map { referenceDate.addingTimeInterval(-TimeInterval($0)) },
                scannedAt: library.scannedAtSecondsAgo.map { referenceDate.addingTimeInterval(-TimeInterval($0)) },
                contentChangedAt: library.contentChangedAtSecondsAgo.map { referenceDate.addingTimeInterval(-TimeInterval($0)) },
                latestAddedAt: latest.map { referenceDate.addingTimeInterval(-TimeInterval($0.addedAtSecondsAgo)) },
                latestItemTitle: latest?.item.title
            ),
            rawType: library.type,
            recentItems: recentItems
        )
    }
}

private struct DebugMockArtwork {
    let url: URL
    let data: Data
    let contentType: String

    static func load(serverURL: URL, mockPath: String, resource: String) -> DebugMockArtwork {
        let sourceURL = PlexMockServerResourceLocator.url(for: resource)
        let data = try! Data(contentsOf: sourceURL)
        return DebugMockArtwork(
            url: PlexURLBuilder.mediaURL(serverURL: serverURL, path: mockPath)!,
            data: data,
            contentType: sourceURL.pathExtension == "png" ? "image/png" : "image/jpeg"
        )
    }
}

private struct PlexDebugMockLibrarySection {
    let library: PlexLibrary
    let rawType: String
    let recentItems: [PlexMockMediaCatalog.Record]
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
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let state = PlexDebugMockStateRegistry.shared.state(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = debugFixture.response(for: request, state: state)
            ?? debugFixture.errorResponse(for: request, status: 404)
        client?.urlProtocol(self, didReceive: response.response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

}

private struct PlexDebugMockResponse {
    let response: HTTPURLResponse
    let data: Data
}

#endif
