import Foundation

struct PlexServerResource: Identifiable, Equatable {
    let id: String
    let name: String
    let productVersion: String?
    let accessToken: String
    let connections: [PlexServerConnection]

    var preferredConnection: PlexServerConnection? {
        connections.sorted(by: PlexServerConnection.preferenceComparator).first
    }

    var selectedURL: URL? {
        preferredConnection?.uri
    }

    var displayProductVersion: String? {
        guard let productVersion = productVersion?.nilIfBlank else {
            return nil
        }

        return productVersion.split(separator: "-", maxSplits: 1).first.map(String.init)
    }

    var connectionSummary: String {
        guard let preferredConnection else {
            return "Unavailable"
        }

        if preferredConnection.relay {
            return "Relay"
        }

        if preferredConnection.local {
            return "Local"
        }

        return "Remote"
    }
}

struct PlexServerConnection: Equatable {
    let uri: URL
    let local: Bool
    let relay: Bool

    fileprivate static func preferenceComparator(lhs: PlexServerConnection, rhs: PlexServerConnection) -> Bool {
        let lhsScore = (lhs.local ? 0 : 1, lhs.relay ? 1 : 0)
        let rhsScore = (rhs.local ? 0 : 1, rhs.relay ? 1 : 0)
        return lhsScore < rhsScore
    }
}
