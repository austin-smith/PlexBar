import Foundation

public enum PlexConnectionKind: String, Codable, Sendable {
    case local
    case remote
    case relay

    public var displayName: String {
        switch self {
        case .local:
            return "Local"
        case .remote:
            return "Remote"
        case .relay:
            return "Relay"
        }
    }
}

public struct PlexResolvedConnection: Equatable, Sendable {
    public let serverID: String
    public let url: URL
    public let kind: PlexConnectionKind
    public let validatedAt: Date

    public init(
        serverID: String,
        url: URL,
        kind: PlexConnectionKind,
        validatedAt: Date
    ) {
        self.serverID = serverID
        self.url = url
        self.kind = kind
        self.validatedAt = validatedAt
    }
}
