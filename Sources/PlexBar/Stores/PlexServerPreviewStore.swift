import Foundation
import Observation

@MainActor
@Observable
final class PlexServerPreviewStore {
    private let client: PlexAPIClient
    private let resolver: PlexConnectionResolver
    private var loadTasksByServerID: [String: Task<Void, Never>] = [:]
    private var loadRequestIDsByServerID: [String: UUID] = [:]
    private var statesByServerID: [String: PlexServerPreviewState] = [:]

    init(
        client: PlexAPIClient = PlexAPIClient(),
        resolver: PlexConnectionResolver = PlexConnectionResolver()
    ) {
        self.client = client
        self.resolver = resolver
    }

    func state(for serverID: String?) -> PlexServerPreviewState {
        guard let serverID else {
            return .empty
        }

        return statesByServerID[serverID] ?? .empty
    }

    func reconcileServers(_ servers: [PlexServerResource]) {
        let serverIDs = Set(servers.map(\.id))
        let removedServerIDs = Set(statesByServerID.keys).union(loadTasksByServerID.keys).subtracting(serverIDs)

        for serverID in removedServerIDs {
            loadTasksByServerID[serverID]?.cancel()
            loadTasksByServerID[serverID] = nil
            loadRequestIDsByServerID[serverID] = nil
            statesByServerID[serverID] = nil
        }
    }

    func loadPreviewsIfNeeded(
        for servers: [PlexServerResource],
        clientIdentifier: String
    ) {
        let pendingServers = servers.filter { server in
            let state = state(for: server.id)
            return state.hasLoaded == false
                && state.isLoading == false
                && loadTasksByServerID[server.id] == nil
        }

        guard !pendingServers.isEmpty else {
            return
        }

        loadPreviews(for: pendingServers, clientIdentifier: clientIdentifier, forceReload: false)
    }

    func refreshPreviews(
        for servers: [PlexServerResource],
        clientIdentifier: String
    ) {
        guard !servers.isEmpty else {
            return
        }

        loadPreviews(for: servers, clientIdentifier: clientIdentifier, forceReload: true)
    }

    private func loadPreviews(
        for servers: [PlexServerResource],
        clientIdentifier: String,
        forceReload: Bool
    ) {
        for server in servers {
            if forceReload {
                loadTasksByServerID[server.id]?.cancel()
                loadTasksByServerID[server.id] = nil
            }

            var state = state(for: server.id)
            state.isLoading = true
            state.errorMessage = nil
            statesByServerID[server.id] = state
            let client = self.client
            let requestID = UUID()
            loadRequestIDsByServerID[server.id] = requestID

            loadTasksByServerID[server.id] = Task {
                let result = await loadResult(
                    for: server,
                    clientIdentifier: clientIdentifier,
                    client: client
                )

                await MainActor.run {
                    guard loadRequestIDsByServerID[server.id] == requestID else {
                        return
                    }

                    loadTasksByServerID[server.id] = nil
                    loadRequestIDsByServerID[server.id] = nil
                    apply(result)
                }
            }
        }
    }

    private func loadResult(
        for server: PlexServerResource,
        clientIdentifier: String,
        client: PlexAPIClient
    ) async -> ServerPreviewLoadResult {
        do {
            let resolvedConnection = try await resolver.resolve(
                server: server,
                clientContext: PlexClientContext(clientIdentifier: clientIdentifier),
                cachedURL: nil
            )
            let configuration = PlexConnectionConfiguration(
                serverURL: resolvedConnection.url,
                token: server.accessToken,
                clientContext: PlexClientContext(clientIdentifier: clientIdentifier)
            )
            let items = try await client.fetchRecentAddedPreviewItems(using: configuration)
            return .success(
                serverID: server.id,
                preview: PlexServerPreview(
                    serverID: server.id,
                    serverURL: resolvedConnection.url,
                    items: items,
                    generatedAt: Date()
                )
            )
        } catch is CancellationError {
            return .cancelled(serverID: server.id)
        } catch {
            return .failure(
                serverID: server.id,
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func apply(_ result: ServerPreviewLoadResult) {
        switch result {
        case .success(let serverID, let preview):
            statesByServerID[serverID] = PlexServerPreviewState(
                preview: preview,
                isLoading: false,
                hasLoaded: true,
                errorMessage: nil
            )
        case .failure(let serverID, let errorMessage):
            statesByServerID[serverID] = PlexServerPreviewState(
                preview: nil,
                isLoading: false,
                hasLoaded: false,
                errorMessage: errorMessage
            )
        case .cancelled(let serverID):
            guard var state = statesByServerID[serverID] else {
                return
            }

            state.isLoading = false
            statesByServerID[serverID] = state
        }
    }
}

private enum ServerPreviewLoadResult {
    case success(serverID: String, preview: PlexServerPreview)
    case failure(serverID: String, errorMessage: String)
    case cancelled(serverID: String)
}
