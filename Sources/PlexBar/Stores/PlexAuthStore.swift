import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PlexAuthStore {
    private let settings: PlexSettingsStore
    private let sessionStore: PlexSessionStore
    private let client: PlexAuthClient
    private var signInTask: Task<Void, Never>?

    var availableServers: [PlexServerResource] = []
    var isAuthenticating = false
    var isLoadingServers = false
    var statusMessage: String?
    var errorMessage: String?
    var remainingSeconds: Int?

    init(settings: PlexSettingsStore, sessionStore: PlexSessionStore, client: PlexAuthClient = PlexAuthClient()) {
        self.settings = settings
        self.sessionStore = sessionStore
        self.client = client

        if settings.hasAuthenticatedAccount {
            Task {
                await refreshServers(autoSelectStoredServer: true)
            }
        }
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
        isLoadingServers = false
        statusMessage = nil
        errorMessage = nil
        remainingSeconds = nil
        availableServers = []
        settings.clearAuthentication()
        sessionStore.refreshNow()
    }

    private func selectServer(_ server: PlexServerResource) {
        settings.saveServerSelection(server)
        sessionStore.refreshNow()
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
                    await refreshServers(autoSelectStoredServer: true)
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
