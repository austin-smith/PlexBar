import Foundation

/// Keeps transport causes without retaining authenticated URLs or request headers.
public struct PlexServerConnectionFailure: LocalizedError, Sendable {
    public let serverName: String
    public let failureCodes: [URLError.Code]

    public var errorDescription: String? {
        var uniqueCodes: [URLError.Code] = []
        for code in failureCodes where !uniqueCodes.contains(code) {
            uniqueCodes.append(code)
        }
        let reasons = uniqueCodes.map { URLError($0).localizedDescription }
        return (["PlexBar could not reach any advertised connection for \(serverName)."] + reasons)
            .joined(separator: "\n\n")
    }

    public init(
        serverName: String,
        failureCodes: [URLError.Code]
    ) {
        self.serverName = serverName
        self.failureCodes = failureCodes
    }
}

public struct PlexServerResource: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let productVersion: String?
    public let accessToken: String
    public let connections: [PlexServerConnection]

    public var displayProductVersion: String? {
        guard let productVersion = productVersion?.nilIfBlank else {
            return nil
        }

        return productVersion.split(separator: "-", maxSplits: 1).first.map(String.init)
    }

    public var preferredConnection: PlexServerConnection? {
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

    public init(
        id: String,
        name: String,
        productVersion: String? = nil,
        accessToken: String,
        connections: [PlexServerConnection]
    ) {
        self.id = id
        self.name = name
        self.productVersion = productVersion
        self.accessToken = accessToken
        self.connections = connections
    }
}

public struct PlexServerConnection: Equatable, Hashable, Sendable {
    public let uri: URL
    public let local: Bool
    public let relay: Bool

    public var kind: PlexConnectionKind {
        if relay {
            return .relay
        }

        return local ? .local : .remote
    }

    public var priorityTier: Int {
        switch kind {
        case .local:
            return 0
        case .remote:
            return 1
        case .relay:
            return 2
        }
    }

    public init(
        uri: URL,
        local: Bool,
        relay: Bool
    ) {
        self.uri = uri
        self.local = local
        self.relay = relay
    }
}
