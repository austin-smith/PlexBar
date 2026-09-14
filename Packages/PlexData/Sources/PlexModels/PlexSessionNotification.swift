import Foundation

public enum PlexSessionEvent: Equatable, Sendable {
    case connected
    case playing(PlexPlaySessionStateNotification)
    case transcodeSessionUpdate(PlexTranscodeSessionUpdate)
}

public struct PlexSessionNotificationEnvelope: Decodable, Sendable {
    public let notificationContainer: PlexSessionNotificationContainer

    enum CodingKeys: String, CodingKey {
        case notificationContainer = "NotificationContainer"
    }

    public init(
        notificationContainer: PlexSessionNotificationContainer
    ) {
        self.notificationContainer = notificationContainer
    }
}

public struct PlexSessionNotificationContainer: Decodable, Sendable {
    public let type: String?
    public let playbackStateNotifications: [PlexPlaySessionStateNotification]
    public let transcodeSessionUpdateNotifications: [PlexTranscodeSessionUpdate]

    enum CodingKeys: String, CodingKey {
        case type
        case playbackStateNotifications = "PlaySessionStateNotification"
        case transcodeSessionUpdateNotifications = "TranscodeSession"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        playbackStateNotifications = try container.decodeIfPresent([PlexPlaySessionStateNotification].self, forKey: .playbackStateNotifications) ?? []
        transcodeSessionUpdateNotifications = try container.decodeIfPresent([PlexTranscodeSessionUpdate].self, forKey: .transcodeSessionUpdateNotifications) ?? []
    }

    public var sessionEvents: [PlexSessionEvent] {
        let normalizedType = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalizedType {
        case "playing":
            return playbackStateNotifications.map(PlexSessionEvent.playing)
        case "transcodesession.update":
            // Decoded for contract coverage; the store currently ignores routine transcode progress events.
            return transcodeSessionUpdateNotifications.map(PlexSessionEvent.transcodeSessionUpdate)
        default:
            return []
        }
    }
}

public struct PlexPlaySessionStateNotification: Decodable, Equatable, Sendable {
    public let sessionKey: String?
    public let state: String?
    public let viewOffset: Int?
    public let ratingKey: String?
    public let key: String?
    public let transcodeSessionKey: String?
    public let hasViewOffset: Bool
    public let hasRatingKey: Bool
    public let hasKey: Bool
    public let hasTranscodeSession: Bool

    enum CodingKeys: String, CodingKey {
        case sessionKey
        case state
        case viewOffset
        case ratingKey
        case key
        case transcodeSession
    }

    public init(
        sessionKey: String?,
        state: String?,
        viewOffset: Int?,
        ratingKey: String?,
        key: String?,
        transcodeSessionKey: String?,
        hasViewOffset: Bool = true,
        hasRatingKey: Bool = true,
        hasKey: Bool = true,
        hasTranscodeSession: Bool = true
    ) {
        self.sessionKey = sessionKey
        self.state = state
        self.viewOffset = viewOffset
        self.ratingKey = ratingKey
        self.key = key
        self.transcodeSessionKey = transcodeSessionKey
        self.hasViewOffset = hasViewOffset
        self.hasRatingKey = hasRatingKey
        self.hasKey = hasKey
        self.hasTranscodeSession = hasTranscodeSession
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionKey = try container.decodeIfPresent(String.self, forKey: .sessionKey)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        hasViewOffset = container.contains(.viewOffset)
        viewOffset = try container.decodeIfPresent(Int.self, forKey: .viewOffset)
        hasRatingKey = container.contains(.ratingKey)
        ratingKey = try container.decodeIfPresent(String.self, forKey: .ratingKey)
        hasKey = container.contains(.key)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        hasTranscodeSession = container.contains(.transcodeSession)
        let transcodeID = try container.decodeIfPresent(String.self, forKey: .transcodeSession)
        // Notifications carry the bare ID; HTTP session snapshots carry this path.
        transcodeSessionKey = transcodeID
            .flatMap { $0.nilIfBlank }
            .map { "/transcode/sessions/\($0)" }
    }
}

public struct PlexTranscodeSessionUpdate: Decodable, Equatable, Sendable {
    public let key: String?

    public init(
        key: String? = nil
    ) {
        self.key = key
    }
}
