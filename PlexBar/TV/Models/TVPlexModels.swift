import Foundation

struct TVPlexConnection: Equatable, Sendable {
    let serverURL: URL
    let token: String
    let clientIdentifier: String
    let serverIdentifier: String
    let kind: PlexConnectionKind
}

struct TVPlexServerIdentity: Decodable, Sendable {
    let machineIdentifier: String?
    let friendlyName: String?
    let version: String?
}

struct TVPlexResolvedServer: Sendable {
    let connection: TVPlexConnection
    let identity: TVPlexServerIdentity
}

enum TVPlaybackPreparationKind: Equatable, Sendable {
    case content
    case primaryExtra
}

struct TVPlaybackPreparation: Equatable, Sendable {
    let itemRatingKey: String
    let kind: TVPlaybackPreparationKind
}

struct TVPlexIdentityEnvelope: Decodable, Sendable {
    let mediaContainer: TVPlexServerIdentity

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct TVPlexLibrary: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let type: String
    let thumb: String?
    let art: String?
    let composite: String?
    var recentArtworkPath: String?

    var artworkPath: String? { composite ?? recentArtworkPath ?? art ?? thumb }

    private enum CodingKeys: String, CodingKey {
        case key
        case title
        case type
        case thumb
        case art
        case composite
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexStringIfPresent(forKey: .key) ?? UUID().uuidString
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "Library"
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
        thumb = try values.decodeIfPresent(String.self, forKey: .thumb)?.nilIfBlank
        art = try values.decodeIfPresent(String.self, forKey: .art)?.nilIfBlank
        composite = try values.decodeIfPresent(String.self, forKey: .composite)?.nilIfBlank
    }
}

struct TVPlexPlaybackRequest: Identifiable, Sendable {
    let item: PlexMediaItem
    let queue: PlexPlaybackQueue?
    let source: PlexPlaybackSource?
    let queueSourcePreference: PlexPlaybackQueueSourcePreference?
    let startTime: TimeInterval
    let autoplay: Bool
    let playbackRate: PlexPlaybackRate
    let videoQualityOverride: PlexVideoQuality?
    let forceVideoTranscode: Bool
    let id: UUID
    let sessionIdentifier: String

    init(
        item: PlexMediaItem,
        queue: PlexPlaybackQueue? = nil,
        source: PlexPlaybackSource? = nil,
        queueSourcePreference: PlexPlaybackQueueSourcePreference? = nil,
        startTime: TimeInterval,
        autoplay: Bool = true,
        playbackRate: PlexPlaybackRate = .normal,
        videoQualityOverride: PlexVideoQuality? = nil,
        forceVideoTranscode: Bool = false
    ) {
        let id = UUID()
        self.init(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: startTime,
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode,
            id: id,
            sessionIdentifier: id.uuidString.lowercased()
        )
    }

    private init(
        item: PlexMediaItem,
        queue: PlexPlaybackQueue?,
        source: PlexPlaybackSource?,
        queueSourcePreference: PlexPlaybackQueueSourcePreference?,
        startTime: TimeInterval,
        autoplay: Bool,
        playbackRate: PlexPlaybackRate,
        videoQualityOverride: PlexVideoQuality?,
        forceVideoTranscode: Bool,
        id: UUID,
        sessionIdentifier: String
    ) {
        self.item = item
        self.queue = queue
        self.source = source
        self.queueSourcePreference = queueSourcePreference
        self.startTime = startTime
        self.autoplay = autoplay
        self.playbackRate = playbackRate
        self.videoQualityOverride = videoQualityOverride
        self.forceVideoTranscode = forceVideoTranscode
        self.id = id
        self.sessionIdentifier = sessionIdentifier
    }

    func startingNewPlaybackSession(
        at startTime: TimeInterval,
        playbackRate: PlexPlaybackRate
    ) -> Self {
        Self(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: startTime,
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode,
            id: id,
            sessionIdentifier: UUID().uuidString.lowercased()
        )
    }

    func withPlaybackRate(_ playbackRate: PlexPlaybackRate) -> Self {
        Self(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: startTime,
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode,
            id: id,
            sessionIdentifier: sessionIdentifier
        )
    }

    func withQueue(_ queue: PlexPlaybackQueue) -> Self {
        Self(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: startTime,
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode,
            id: id,
            sessionIdentifier: sessionIdentifier
        )
    }
}

struct TVPlexLibrariesEnvelope: Decodable, Sendable {
    let mediaContainer: Container

    struct Container: Decodable, Sendable {
        let directories: [TVPlexLibrary]

        private enum CodingKeys: String, CodingKey {
            case directories = "Directory"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            directories = try values.decodeIfPresent([TVPlexLibrary].self, forKey: .directories) ?? []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}


enum TVPlexError: LocalizedError, Sendable {
    case notConnected
    case invalidServerURL
    case invalidResponse
    case badStatus(Int)
    case decodingFailed
    case noPlayableMedia
    case playbackRejected(String)
    case serverIdentityMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Connect to a Plex server before loading this content."
        case .invalidServerURL: "Plex returned an invalid connection URL."
        case .invalidResponse: "The Plex server returned an invalid response."
        case .badStatus(let status): "The Plex server returned HTTP \(status)."
        case .decodingFailed: "Plex returned media data this version could not read."
        case .noPlayableMedia: "This item has no playable media."
        case .playbackRejected(let reason): "Plex rejected playback: \(reason)"
        case .serverIdentityMismatch(let expected, let actual):
            "PlexBar expected server \(expected), but the connection reported \(actual)."
        }
    }
}
