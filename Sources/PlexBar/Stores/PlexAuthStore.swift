import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PlexAuthStore {
    private let settings: PlexSettingsStore
    private let connectionStore: PlexConnectionStore
    private let sessionStore: PlexSessionStore
    private let historyStore: PlexHistoryStore
    private let libraryStore: PlexLibraryStore
    private let client: PlexAuthClient
    private var signInTask: Task<Void, Never>?

    var authenticatedUser: PlexAuthenticatedUser?
    var availableServers: [PlexServerResource] = []
    var isAuthenticating = false
    var isLoadingAuthenticatedUser = false
    var isLoadingServers = false
    var accountErrorMessage: String?
    var statusMessage: String?
    var errorMessage: String?
    var remainingSeconds: Int?

    init(
        settings: PlexSettingsStore,
        connectionStore: PlexConnectionStore,
        sessionStore: PlexSessionStore,
        historyStore: PlexHistoryStore,
        libraryStore: PlexLibraryStore,
        client: PlexAuthClient = PlexAuthClient()
    ) {
        self.settings = settings
        self.connectionStore = connectionStore
        self.sessionStore = sessionStore
        self.historyStore = historyStore
        self.libraryStore = libraryStore
        self.client = client

        if settings.hasAuthenticatedAccount {
            Task {
                await refreshAuthenticatedState(autoSelectStoredServer: true)
            }
        }
    }

    func refreshAuthenticatedUser() async {
        guard settings.hasAuthenticatedAccount else {
            authenticatedUser = nil
            accountErrorMessage = nil
            isLoadingAuthenticatedUser = false
            return
        }

        isLoadingAuthenticatedUser = true
        accountErrorMessage = nil

        let clientContext = PlexClientContext(clientIdentifier: settings.clientIdentifier)

        do {
            authenticatedUser = try await client.fetchAuthenticatedUser(
                userToken: settings.trimmedUserToken,
                clientContext: clientContext
            )
        } catch {
            authenticatedUser = nil
            accountErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoadingAuthenticatedUser = false
    }

    func startSignIn() {
        guard !isAuthenticating else {
            return
        }

        signInTask?.cancel()
        let clientIdentifier = settings.rotateClientIdentifier()
        signInTask = Task {
            await runSignIn(clientIdentifier: clientIdentifier)
        }
    }

    func refreshServers(autoSelectStoredServer: Bool = false) async {
        guard settings.hasAuthenticatedAccount else {
            availableServers = []
            return
        }

        isLoadingServers = true
        errorMessage = nil

        let clientContext = PlexClientContext(clientIdentifier: settings.clientIdentifier)

        do {
            let servers = try await client.fetchServers(
                userToken: settings.trimmedUserToken,
                clientContext: clientContext
            )

            guard !servers.isEmpty else {
                throw PlexAuthError.noServersFound
            }

            availableServers = servers
            connectionStore.updateAvailableServers(servers)

            if autoSelectStoredServer,
               let selectedServerIdentifier = settings.selectedServerIdentifier,
               let storedServer = servers.first(where: { $0.id == selectedServerIdentifier }) {
                selectServer(storedServer)
            } else if settings.selectedServerIdentifier == nil || !servers.contains(where: { $0.id == settings.selectedServerIdentifier }) {
                selectServer(servers[0])
            }

            statusMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoadingServers = false
    }

    func selectServer(withID serverID: String) {
        guard let server = availableServers.first(where: { $0.id == serverID }) else {
            return
        }

        selectServer(server)
    }

    func signOut() {
        signInTask?.cancel()
        isAuthenticating = false
        isLoadingAuthenticatedUser = false
        isLoadingServers = false
        authenticatedUser = nil
        accountErrorMessage = nil
        statusMessage = nil
        errorMessage = nil
        remainingSeconds = nil
        availableServers = []
        settings.clearAuthentication()
        connectionStore.updateAvailableServers([])
        sessionStore.didChangeConfiguration()
        historyStore.refreshNow()
    }

    private func selectServer(_ server: PlexServerResource) {
        settings.saveServerSelection(server)
        connectionStore.didSelectServer()
        sessionStore.didChangeConfiguration()
        historyStore.refreshNow()
    }

    private func refreshAuthenticatedState(autoSelectStoredServer: Bool) async {
        async let authenticatedUserRefresh: Void = refreshAuthenticatedUser()
        async let serverRefresh: Void = refreshServers(autoSelectStoredServer: autoSelectStoredServer)
        _ = await (authenticatedUserRefresh, serverRefresh)
    }

    private func runSignIn(clientIdentifier: String) async {
        isAuthenticating = true
        statusMessage = "Waiting for authentication in your browser…"
        errorMessage = nil
        remainingSeconds = nil

        let clientContext = PlexClientContext(clientIdentifier: clientIdentifier)

        do {
            let pin = try await client.createPin(clientContext: clientContext)
            guard let authURL = clientContext.authURL(for: pin.code) else {
                throw PlexAuthError.invalidAuthURL
            }

            NSWorkspace.shared.open(authURL)

            for seconds in stride(from: 120, through: 1, by: -1) {
                remainingSeconds = seconds

                let currentPin = try await client.fetchPin(id: String(pin.id), clientContext: clientContext)
                if let authToken = currentPin.authToken?.nilIfBlank {
                    settings.saveAuthenticatedUserToken(authToken)
                    statusMessage = "Authentication successful."
                    remainingSeconds = nil
                    isAuthenticating = false
                    await refreshAuthenticatedState(autoSelectStoredServer: true)
                    return
                }

                try await Task.sleep(for: .seconds(1))
            }

            statusMessage = nil
            errorMessage = "Authentication timed out. Please try again."
        } catch {
            statusMessage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        remainingSeconds = nil
        isAuthenticating = false
    }
}
