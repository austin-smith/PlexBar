import Foundation
import PlexModels

public struct PlexMockServerPayload: Decodable, Sendable {
    public let authenticatedUserID: Int
    public let server: Server
    public let users: [User]
    public let activeSessions: [ActiveSession]
    public let historyEvents: [HistoryEvent]
    public let libraries: [Library]
    public let artwork: [Artwork]

}

extension PlexMockServerPayload {
    public struct Server: Decodable, Sendable {
        public let id: String
        public let name: String
        public let productVersion: String?
        public let accessToken: String
        public let connections: [Connection]

        public func materialize() -> PlexServerResource {
            PlexServerResource(
                id: id,
                name: name,
                productVersion: productVersion,
                accessToken: accessToken,
                connections: connections.map { $0.materialize() }
            )
        }
    }

    public struct Connection: Decodable, Sendable {
        public let uri: URL
        public let local: Bool
        public let relay: Bool

        public func materialize() -> PlexServerConnection {
            PlexServerConnection(uri: uri, local: local, relay: relay)
        }
    }

    public struct User: Codable, Equatable, Identifiable, Sendable {
        public let id: Int
        public var name: String { friendlyName?.nilIfBlank ?? username }
        public var username: String
        public var email: String?
        public var friendlyName: String?
        public var avatar: String?
        public var devices: [Device]

        public func materialize() -> PlexAccount {
            PlexAccount(id: id, name: name, thumb: avatar)
        }

        public func materializeUser() -> PlexUser {
            PlexUser(id: String(id), thumb: avatar, title: name)
        }

        public func materializeAuthenticatedUser(thumbOverride: String? = nil) -> PlexAuthenticatedUser {
            PlexAuthenticatedUser(id: id, username: username, title: name,
                                  email: email?.nilIfBlank, thumb: thumbOverride ?? avatar,
                                  friendlyName: friendlyName?.nilIfBlank)
        }
    }

    public struct Device: Codable, Equatable, Identifiable, Sendable {
        public let id: Int
        public var title: String
        public var machineIdentifier: String
        public var platform: String?
        public var product: String?
        public var connection: DeviceConnection

        public init(id: Int, title: String, machineIdentifier: String, platform: String? = nil,
                    product: String? = nil, connection: DeviceConnection = .init()) {
            self.id = id
            self.title = title
            self.machineIdentifier = machineIdentifier
            self.platform = platform
            self.product = product
            self.connection = connection
        }

        public func materializePlayer(state: String?) -> PlexPlayer {
            PlexPlayer(address: connection.address, machineIdentifier: machineIdentifier,
                       platform: platform, product: product, remotePublicAddress: connection.remotePublicAddress,
                       state: state, title: title, local: connection.local,
                       relayed: connection.relayed, secure: connection.secure)
        }

        public func materializeHistoryDevice() -> PlexHistoryDevice {
            PlexHistoryDevice(id: id, name: title, platform: platform)
        }
    }

    /// The connection used by this mock device. Playback state belongs to each activity record.
    public struct DeviceConnection: Codable, Equatable, Sendable {
        public var address: String?
        public var remotePublicAddress: String?
        public var resolvedLocation: String?
        public var local: Bool?
        public var relayed: Bool?
        public var secure: Bool?

        public init() {}

        public var sessionLocation: String? {
            local.map { $0 ? "lan" : "wan" }
        }
    }

    public struct Artwork: Decodable, Sendable {
        public let path: String
        public let resource: String
    }

    public struct ActiveSession: Decodable, Sendable {
        public let sessionKey: String
        public let userID: Int
        public let mediaType: String
        public let mediaID: String
        public let viewOffset: Int?
        public let deviceID: Int
        public let state: String?
        public let session: PlaybackSession?
        public let transcodeSession: PlexTranscodeSession?
        public let mediaDecision: String?
        public let mediaStreams: [PlexStream]?
        public let audioStream: AudioStream?
    }

    public struct AudioStream: Decodable, Sendable {
        public let id: Int
        public let streamType: Int
        public let codec: String?
        public let selected: Bool?
        public let levels: [Double]
    }

    public struct HistoryEvent: Decodable, Sendable {
        public let historyKey: String
        public let userID: Int
        public let mediaType: String
        public let mediaID: String
        public let viewedAtSecondsAgo: Int
        public let deviceID: Int?
    }

    public struct Library: Decodable, Sendable {
        public let id: String
        public let title: String
        public let type: String
        public let updatedAtSecondsAgo: Int?
        public let scannedAtSecondsAgo: Int?
        public let contentChangedAtSecondsAgo: Int?
        public let entries: [LibraryEntry]
    }

    public struct LibraryEntry: Decodable, Sendable {
        public let mediaID: String
    }

    public struct PlaybackSession: Decodable, Sendable {
        public let id: String?
        public let bandwidth: Int?

        public func materialize(location: String?) -> PlexPlaybackSession {
            PlexPlaybackSession(id: id, bandwidth: bandwidth, location: location)
        }
    }

}
