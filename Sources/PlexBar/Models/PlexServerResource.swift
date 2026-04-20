import Foundation

struct PlexServerResource: Identifiable, Equatable {
    let id: String
    let name: String
    let productVersion: String?
    let accessToken: String
    let connections: [PlexServerConnection]

    var displayProductVersion: String? {
        guard let productVersion = productVersion?.nilIfBlank else {
            return nil
        }

        return productVersion.split(separator: "-", maxSplits: 1).first.map(String.init)
    }
}

struct PlexServerConnection: Equatable {
    let uri: URL
    let local: Bool
    let relay: Bool

    var kind: PlexConnectionKind {
        if relay {
            return .relay
        }

        return local ? .local : .remote
    }

    var priorityTier: Int {
        switch kind {
        case .local:
            return 0
        case .remote:
            return 1
        case .relay:
            return 2
        }
    }
}
