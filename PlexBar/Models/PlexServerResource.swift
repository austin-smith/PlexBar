import Foundation

/// Keeps transport causes without retaining authenticated URLs or request headers.
struct PlexServerConnectionFailure: LocalizedError, Sendable {
    let serverName: String
    let failureCodes: [URLError.Code]

    var errorDescription: String? {
        var uniqueCodes: [URLError.Code] = []
        for code in failureCodes where !uniqueCodes.contains(code) {
            uniqueCodes.append(code)
        }
        let reasons = uniqueCodes.map { URLError($0).localizedDescription }
        return (["PlexBar could not reach any advertised connection for \(serverName)."] + reasons)
            .joined(separator: "\n\n")
    }
}

struct PlexServerResource: Identifiable, Equatable, Hashable, Sendable {
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

    var preferredConnection: PlexServerConnection? {
        connections.min { lhs, rhs in
            if lhs.priorityTier != rhs.priorityTier {
                return lhs.priorityTier < rhs.priorityTier
            }

            let lhsIsHTTPS = lhs.uri.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame
            let rhsIsHTTPS = rhs.uri.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame
            if lhsIsHTTPS != rhsIsHTTPS {
                return lhsIsHTTPS
            }

            return lhs.uri.absoluteString.localizedCaseInsensitiveCompare(rhs.uri.absoluteString) == .orderedAscending
        }
    }
}

struct PlexServerConnection: Equatable, Hashable, Sendable {
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
