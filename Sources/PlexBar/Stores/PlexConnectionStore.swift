import Foundation
import Observation

@MainActor
@Observable
final class PlexConnectionStore {
    let settings: PlexSettingsStore
    private let resolver: PlexConnectionResolver
    private var serversByID: [String: PlexServerResource] = [:]

    var activeConnection: PlexResolvedConnection?
    var isResolving = false
    var errorMessage: String?

    init(
        settings: PlexSettingsStore,
        resolver: PlexConnectionResolver = PlexConnectionResolver()
    ) {
        self.settings = settings
        self.resolver = resolver
    }

    var activeConnectionKind: PlexConnectionKind? {
        activeConnection?.kind
    }

    var resolvedServerURL: URL? {
        activeConnection?.url ?? settings.normalizedServerURL
    }

    var hasSelectedServerResource: Bool {
        selectedServer != nil
    }

    func updateAvailableServers(_ servers: [PlexServerResource]) {
        serversByID = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })

        guard let selectedServerIdentifier = settings.selectedServerIdentifier else {
            activeConnection = nil
            errorMessage = nil
            settings.clearCachedConnection()
            return
        }

        guard let selectedServer = serversByID[selectedServerIdentifier] else {
            activeConnection = nil
            errorMessage = nil
            settings.clearCachedConnection()
            return
        }

        if let activeConnection,
           activeConnection.serverID == selectedServer.id,
           selectedServer.connections.contains(where: { $0.uri == activeConnection.url }) {
            return
        }

        activeConnection = nil
    }

    func didSelectServer() {
        activeConnection = nil
        errorMessage = nil
    }

    func currentConfiguration(forceRefresh: Bool = false) async throws -> PlexConnectionConfiguration {
        guard settings.hasValidConfiguration else {
            throw PlexConnectionStoreError.noSelectedServer
        }

        if !forceRefresh,
           let activeConnection,
           activeConnection.serverID == settings.selectedServerIdentifier {
            return PlexConnectionConfiguration(
                serverURL: activeConnection.url,
                token: settings.trimmedServerToken,
                clientContext: PlexClientContext(clientIdentifier: settings.clientIdentifier)
            )
        }

        return try await resolveConfiguration(forceRefresh: forceRefresh)
    }

    func perform<T>(_ operation: (PlexConnectionConfiguration) async throws -> T) async throws -> T {
        do {
            let configuration = try await currentConfiguration()
            return try await operation(configuration)
        } catch {
            guard error.isPlexConnectivityFailure else {
                throw error
            }
        }

        let configuration = try await currentConfiguration(forceRefresh: true)
        return try await operation(configuration)
    }

    private func resolveConfiguration(forceRefresh: Bool) async throws -> PlexConnectionConfiguration {
        isResolving = true
        defer { isResolving = false }

        let clientContext = PlexClientContext(clientIdentifier: settings.clientIdentifier)
        do {
            let resolvedConnection: PlexResolvedConnection

            if let selectedServer = selectedServer {
                resolvedConnection = try await resolver.resolve(
                    server: selectedServer,
                    clientContext: clientContext,
                    cachedURL: forceRefresh ? nil : settings.normalizedServerURL
                )
            } else if let selectedServerIdentifier = settings.selectedServerIdentifier,
                      let cachedURL = forceRefresh ? nil : settings.normalizedServerURL {
                resolvedConnection = try await resolver.validateCachedConnection(
                    serverID: selectedServerIdentifier,
                    url: cachedURL,
                    token: settings.trimmedServerToken,
                    clientContext: clientContext,
                    kindHint: settings.cachedConnectionKind
                )
            } else {
                throw PlexConnectionStoreError.unavailableServerSelection
            }

            activeConnection = resolvedConnection
            settings.saveResolvedConnection(resolvedConnection)
            errorMessage = nil

            return PlexConnectionConfiguration(
                serverURL: resolvedConnection.url,
                token: settings.trimmedServerToken,
                clientContext: clientContext
            )
        } catch {
            activeConnection = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    private var selectedServer: PlexServerResource? {
        guard let selectedServerIdentifier = settings.selectedServerIdentifier else {
            return nil
        }

        return serversByID[selectedServerIdentifier]
    }
}
