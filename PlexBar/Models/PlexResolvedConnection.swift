import Foundation

enum PlexConnectionKind: String, Codable, Sendable {
    case local
    case remote
    case relay

    var displayName: String {
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

struct PlexResolvedConnection: Equatable, Sendable {
    let serverID: String
    let url: URL
    let kind: PlexConnectionKind
    let validatedAt: Date
}
