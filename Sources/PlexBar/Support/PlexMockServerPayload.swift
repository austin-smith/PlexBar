import Foundation

#if DEBUG
enum PlexMockServerPayloadError: Error {
    case missingResource
}

enum PlexMockServerResourceLocator {
    static func url(for relativePath: String, filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/MockServer/\(relativePath)")
    }
}

struct PlexMockServerPayload: Decodable {
    let authenticatedUser: AuthenticatedUser
    let server: Server
    let users: [User]
    let movies: [Movie]
    let shows: [Show]
    let episodes: [Episode]
    let audiobooks: [Audiobook]
    let activeSessions: [ActiveSession]
    let resolvedLocationsBySessionKey: [String: String]
    let historyEvents: [HistoryEvent]
    let libraries: [Library]

    static func loadDefault() throws -> PlexMockServerPayload {
        let url = PlexMockServerResourceLocator.url(for: "mock-server.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PlexMockServerPayloadError.missingResource
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PlexMockServerPayload.self, from: data)
    }
}

extension PlexMockServerPayload {
    struct AuthenticatedUser: Decodable {
        let id: Int
        let username: String
        let title: String?
        let email: String?
        let thumb: String?
        let friendlyName: String?

        func materialize(thumbOverride: String? = nil) -> PlexAuthenticatedUser {
            PlexAuthenticatedUser(
                id: id,
                username: username,
                title: title?.nilIfBlank,
                email: email?.nilIfBlank,
                thumb: thumbOverride ?? thumb?.nilIfBlank,
                friendlyName: friendlyName?.nilIfBlank
            )
        }
    }

    struct Server: Decodable {
        let id: String
        let name: String
        let productVersion: String?
        let accessToken: String
        let connections: [Connection]

        func materialize() -> PlexServerResource {
            PlexServerResource(
                id: id,
                name: name,
                productVersion: productVersion,
                accessToken: accessToken,
                connections: connections.map { $0.materialize() }
            )
        }
    }

    struct Connection: Decodable {
        let uri: URL
        let local: Bool
        let relay: Bool

        func materialize() -> PlexServerConnection {
            PlexServerConnection(uri: uri, local: local, relay: relay)
        }
    }

    struct User: Decodable {
        let id: Int
        let name: String
        let avatar: String?

        func materialize() -> PlexAccount {
            PlexAccount(id: id, name: name, thumb: avatar)
        }

        func materializeUser() -> PlexUser {
            PlexUser(id: String(id), thumb: avatar, title: name)
        }
    }

    struct Movie: Decodable {
        let id: String
        let title: String
        let year: Int?
        let poster: String?
        let art: String?
        let originallyAvailableAt: String?
    }

    struct Show: Decodable {
        let id: String
        let title: String
        let poster: String?
        let art: String?
    }

    struct Episode: Decodable {
        let id: String
        let showID: String
        let title: String
        let seasonNumber: Int
        let episodeNumber: Int
        let originallyAvailableAt: String?
    }

    struct Audiobook: Decodable {
        let id: String
        let title: String
        let year: Int?
        let cover: String?
        let art: String?
        let artistTitle: String?
        let albumTitle: String?
        let trackTitle: String?
    }

    struct ActiveSession: Decodable {
        let sessionKey: String
        let userID: Int
        let mediaType: String
        let mediaID: String
        let duration: Int?
        let viewOffset: Int?
        let player: Player
        let session: PlaybackSession?
        let transcodeSession: TranscodeSession?
        let mediaDecision: String?
        let media: [Media]?
        let audioStream: AudioStream?
    }

    struct Media: Decodable {
        let id: String?
        let bitrate: Int?
        let videoCodec: String?
        let audioCodec: String?
        let audioProfile: String?
        let container: String?
        let duration: Int?
        let width: Int?
        let height: Int?
        let audioChannels: Int?
        let videoResolution: String?
        let videoFrameRate: String?
        let videoProfile: String?
        let has64bitOffsets: Bool?
        let hasVoiceActivity: String?
        let optimizedForStreaming: Bool?
        let selected: Bool?
        let part: [Part]?
    }

    struct Part: Decodable {
        let id: String?
        let decision: String?
        let bitrate: Int?
        let videoCodec: String?
        let audioCodec: String?
        let container: String?
        let duration: Int?
        let file: String?
        let key: String?
        let size: Int?
        let width: Int?
        let height: Int?
        let videoProfile: String?
        let has64bitOffsets: Bool?
        let optimizedForStreaming: Bool?
        let selected: Bool?
        let stream: [Stream]?
    }

    struct Stream: Decodable {
        let id: Int?
        let streamType: Int?
        let codec: String?
        let profile: String?
        let bitrate: Int?
        let width: Int?
        let height: Int?
        let displayTitle: String?
        let extendedDisplayTitle: String?
        let decision: String?
        let location: String?
        let channels: Int?
        let audioChannelLayout: String?
        let samplingRate: Int?
        let `default`: Bool?
        let language: String?
        let title: String?
        let selected: Bool?
    }

    struct AudioStream: Decodable {
        let id: Int
        let streamType: Int
        let codec: String?
        let selected: Bool?
        let levels: [Double]
    }

    struct HistoryEvent: Decodable {
        let historyKey: String
        let userID: Int
        let mediaType: String
        let mediaID: String
        let viewedAtSecondsAgo: Int
        let deviceID: Int?
    }

    struct Library: Decodable {
        let id: String
        let title: String
        let type: String
        let updatedAtSecondsAgo: Int?
        let scannedAtSecondsAgo: Int?
        let contentChangedAtSecondsAgo: Int?
        let entries: [LibraryEntry]
        let secondarySummary: SecondarySummary?
    }

    struct LibraryEntry: Decodable {
        let mediaID: String
        let addedAtSecondsAgo: Int
    }

    struct SecondarySummary: Decodable {
        let queryType: Int
        let count: Int
        let label: String
    }

    struct Player: Decodable {
        let address: String?
        let machineIdentifier: String?
        let platform: String?
        let product: String?
        let remotePublicAddress: String?
        let state: String?
        let title: String?
        let local: Bool?
        let relayed: Bool?
        let secure: Bool?

        func materialize() -> PlexPlayer {
            PlexPlayer(
                address: address,
                machineIdentifier: machineIdentifier,
                platform: platform,
                product: product,
                remotePublicAddress: remotePublicAddress,
                state: state,
                title: title,
                local: local,
                relayed: relayed,
                secure: secure
            )
        }
    }

    struct PlaybackSession: Decodable {
        let id: String?
        let bandwidth: Int?
        let location: String?

        func materialize() -> PlexPlaybackSession {
            PlexPlaybackSession(id: id, bandwidth: bandwidth, location: location)
        }
    }

    struct TranscodeSession: Decodable {
        let key: String?
        let videoDecision: String?
        let audioDecision: String?
        let protocolName: String?
        let container: String?
        let videoCodec: String?
        let audioCodec: String?
        let sourceVideoCodec: String?
        let sourceAudioCodec: String?
        let width: Int?
        let height: Int?
        let progress: Double?
        let speed: Double?
        let throttled: Bool?
        let transcodeHwRequested: Bool?
        let transcodeHwFullPipeline: Bool?

        enum CodingKeys: String, CodingKey {
            case key
            case videoDecision
            case audioDecision
            case protocolName = "protocol"
            case container
            case videoCodec
            case audioCodec
            case sourceVideoCodec
            case sourceAudioCodec
            case width
            case height
            case progress
            case speed
            case throttled
            case transcodeHwRequested
            case transcodeHwFullPipeline
        }

        func materialize() -> PlexTranscodeSession {
            PlexTranscodeSession(key: key)
        }
    }
}
#endif
