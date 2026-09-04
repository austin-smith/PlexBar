import Foundation

actor PlexConnectionResolver {
    private let client: PlexAPIClient
    private let probeTimeoutInterval: TimeInterval

    init(client: PlexAPIClient = PlexAPIClient(), probeTimeoutInterval: TimeInterval = 2.5) {
        self.client = client
        self.probeTimeoutInterval = probeTimeoutInterval
    }

    func resolve(
        server: PlexServerResource,
        clientContext: PlexClientContext,
        cachedURL: URL?
    ) async throws -> PlexResolvedConnection {
        if let cachedURL,
           let cachedConnection = server.connections.first(where: { $0.uri == cachedURL }) {
            switch try await probe(
                connection: cachedConnection,
                expectedServerID: server.id,
                token: server.accessToken,
                clientContext: clientContext
            ) {
            case .success(let resolved):
                return resolved
            case .unreachable:
                break
            case .hardFailure(let error):
                throw error
            }
        }

        let tiers = Dictionary(grouping: rankedConnections(for: server.connections), by: \.priorityTier)

        for tier in 0...2 {
            guard let candidates = tiers[tier], !candidates.isEmpty else {
                continue
            }

            if let resolved = try await firstReachableConnection(
                candidates,
                expectedServerID: server.id,
                token: server.accessToken,
                clientContext: clientContext
            ) {
                return resolved
            }
        }

        throw PlexConnectionResolutionError.noReachableConnection(server.name)
    }

    func validateCachedConnection(
        serverID: String,
        url: URL,
        token: String,
        clientContext: PlexClientContext,
        kindHint: PlexConnectionKind?
    ) async throws -> PlexResolvedConnection {
        let connection = PlexServerConnection(
            uri: url,
            local: kindHint == .local,
            relay: kindHint == .relay
        )

        switch try await probe(
            connection: connection,
            expectedServerID: serverID,
            token: token,
            clientContext: clientContext
        ) {
        case .success(let resolved):
            return resolved
        case .hardFailure(let error):
            throw error
        case .unreachable:
            break
        }

        throw PlexConnectionResolutionError.noReachableConnection(url.host ?? "server")
    }

    private func rankedConnections(for connections: [PlexServerConnection]) -> [PlexServerConnection] {
        connections.sorted { lhs, rhs in
            if lhs.priorityTier != rhs.priorityTier {
                return lhs.priorityTier < rhs.priorityTier
            }

            let lhsHTTPS = lhs.uri.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame
            let rhsHTTPS = rhs.uri.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame
            if lhsHTTPS != rhsHTTPS {
                return lhsHTTPS
            }

            return lhs.uri.absoluteString.localizedCaseInsensitiveCompare(rhs.uri.absoluteString) == .orderedAscending
        }
    }

    private func firstReachableConnection(
        _ connections: [PlexServerConnection],
        expectedServerID: String,
        token: String,
        clientContext: PlexClientContext
    ) async throws -> PlexResolvedConnection? {
        for connection in connections {
            switch try await probe(
                connection: connection,
                expectedServerID: expectedServerID,
                token: token,
                clientContext: clientContext
            ) {
            case .success(let resolved):
                return resolved
            case .unreachable:
                continue
            case .hardFailure(let error):
                throw error
            }
        }

        return nil
    }

    private func probe(
        connection: PlexServerConnection,
        expectedServerID: String,
        token: String,
        clientContext: PlexClientContext
    ) async throws -> ConnectionProbeResult {
        let configuration = PlexConnectionConfiguration(
            serverURL: connection.uri,
            token: token,
            clientContext: clientContext
        )

        do {
            let identity = try await client.fetchIdentity(
                using: configuration,
                timeoutInterval: probeTimeoutInterval
            )

            guard identity.machineIdentifier == expectedServerID else {
                return .hardFailure(
                    PlexConnectionResolutionError.identityMismatch(
                        expected: expectedServerID,
                        actual: identity.machineIdentifier,
                        url: connection.uri
                    )
                )
            }

            return .success(PlexResolvedConnection(
                serverID: expectedServerID,
                url: connection.uri,
                kind: connection.kind,
                validatedAt: Date()
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if error.isPlexConnectivityFailure {
                return .unreachable
            }

            return .hardFailure(error)
        }
    }
}

private enum ConnectionProbeResult {
    case success(PlexResolvedConnection)
    case unreachable
    case hardFailure(Error)
}

enum PlexConnectionResolutionError: LocalizedError {
    case noReachableConnection(String)
    case identityMismatch(expected: String, actual: String, url: URL)

    var errorDescription: String? {
        switch self {
        case .noReachableConnection(let serverName):
            return "PlexBar could not reach any advertised connection for \(serverName)."
        case .identityMismatch(let expected, let actual, let url):
            return "PlexBar expected server \(expected) at \(url.host ?? url.absoluteString), but PMS reported \(actual)."
        }
    }
}
