import Foundation

enum PlexSessionEvent: Equatable, Sendable {
    case connected
    case playing(PlexPlaySessionStateNotification)
    case transcodeSessionUpdate(PlexTranscodeSessionUpdate)
}

struct PlexSessionNotificationEnvelope: Decodable {
    let notificationContainer: PlexSessionNotificationContainer

    enum CodingKeys: String, CodingKey {
        case notificationContainer = "NotificationContainer"
    }
}

struct PlexSessionNotificationContainer: Decodable {
    let type: String?
    let playbackStateNotifications: [PlexPlaySessionStateNotification]
    let transcodeSessionUpdateNotifications: [PlexTranscodeSessionUpdate]

    enum CodingKeys: String, CodingKey {
        case type
        case playbackStateNotifications = "PlaySessionStateNotification"
        case transcodeSessionUpdateNotifications = "TranscodeSession"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        playbackStateNotifications = try container.decodeIfPresent([PlexPlaySessionStateNotification].self, forKey: .playbackStateNotifications) ?? []
        transcodeSessionUpdateNotifications = try container.decodeIfPresent([PlexTranscodeSessionUpdate].self, forKey: .transcodeSessionUpdateNotifications) ?? []
    }

    var sessionEvents: [PlexSessionEvent] {
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

struct PlexPlaySessionStateNotification: Decodable, Equatable, Sendable {
    let sessionKey: String?
    let state: String?
    let viewOffset: Int?
    let ratingKey: String?
    let key: String?
    let transcodeSessionKey: String?
    let hasViewOffset: Bool
    let hasRatingKey: Bool
    let hasKey: Bool
    let hasTranscodeSession: Bool

    enum CodingKeys: String, CodingKey {
        case sessionKey
        case state
        case viewOffset
        case ratingKey
        case key
        case transcodeSession
    }

    init(
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

    init(from decoder: Decoder) throws {
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
        transcodeSessionKey = try container.decodeIfPresent(PlexTranscodeSessionReference.self, forKey: .transcodeSession)?.key
    }
}

struct PlexTranscodeSessionUpdate: Decodable, Equatable, Sendable {
    let key: String?
}

private struct PlexTranscodeSessionReference: Decodable {
    let key: String?
}
