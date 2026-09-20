import PlexClientKit
import PlexModels
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
    private let deviceIdentityStore: any PlexDeviceIdentityProviding
    private let accountJWTManager: PlexAccountJWTManager
    private var signInTask: Task<Void, Never>?
    private var accountTokenRefreshTask: Task<Void, Never>?
    private var didLoadCredentials = false

    var authenticatedUser: PlexAuthenticatedUser?
    var availableServers: [PlexServerResource] = []
    var isAuthenticating = false
    var isLoadingAuthenticatedUser = false
    var isLoadingServers = false
    var accountErrorMessage: String?
    var statusMessage: String?
    var errorMessage: String?
    var remainingSeconds: Int?
    private(set) var canCancelSignIn = false

    var signInProgressMessage: String? {
        guard let statusMessage else {
            return nil
        }
        guard let remainingSeconds else {
            return statusMessage
        }

        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return "\(statusMessage) \(minutes):" + String(format: "%02d", seconds)
    }

    init(
        settings: PlexSettingsStore,
        connectionStore: PlexConnectionStore,
        sessionStore: PlexSessionStore,
        historyStore: PlexHistoryStore,
        libraryStore: PlexLibraryStore,
        client: PlexAuthClient = PlexAuthClient(),
        deviceIdentityStore: any PlexDeviceIdentityProviding = PlexKeychainDeviceIdentityStore(keychain: KeychainStore(service: AppConstants.bundleIdentifier)),
        accountJWTManager: PlexAccountJWTManager? = nil
    ) {
        self.settings = settings
        self.connectionStore = connectionStore
        self.sessionStore = sessionStore
        self.historyStore = historyStore
        self.libraryStore = libraryStore
        self.client = client
        self.deviceIdentityStore = deviceIdentityStore
        self.accountJWTManager = accountJWTManager ?? PlexAccountJWTManager(
            storage: settings,
            clientContext: { PlexClientContext(clientIdentifier: $0) },
            client: client,
            deviceIdentityStore: deviceIdentityStore
        )
    }

    func credentialsDidLoad() async {
        guard settings.hasLoadedCredentials, !didLoadCredentials else {
            return
        }
        didLoadCredentials = true
        if settings.hasAuthenticatedAccount {
            await refreshAuthenticatedState(autoSelectStoredServer: true)
        }
    }

    func refreshAuthenticatedUser() async {
        guard settings.hasAuthenticatedAccount else {
            authenticatedUser = nil
            accountErrorMessage = nil
            isLoadingAuthenticatedUser = false
            return
        }

        await loadAuthenticatedUser()
    }

    func startSignIn() {
        guard !isAuthenticating else {
            return
        }

        signInTask?.cancel()
        signInTask = Task {
            await runSignIn()
        }
    }

    func cancelSignIn() {
        guard canCancelSignIn else {
            return
        }
        signInTask?.cancel()
        signInTask = nil
        clearSignInPresentation()
    }

    func refreshServers(autoSelectStoredServer: Bool = false) async {
        guard settings.hasAuthenticatedAccount else {
            availableServers = []
            return
        }

        await loadServers(autoSelectStoredServer: autoSelectStoredServer)
    }

    func selectServer(withID serverID: String) {
        guard settings.hasAuthenticatedAccount,
              let server = availableServers.first(where: { $0.id == serverID }) else {
            return
        }

        selectServer(server)
    }

    func signOut() {
        accountJWTManager.invalidatePreparation()
        signInTask?.cancel()
        accountTokenRefreshTask?.cancel()
        isAuthenticating = false
        canCancelSignIn = false
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
        async let authenticatedUserRefresh: Void = loadAuthenticatedUser()
        async let serverRefresh: Void = loadServers(
            autoSelectStoredServer: autoSelectStoredServer
        )
        _ = await (authenticatedUserRefresh, serverRefresh)
    }

    private func runSignIn() async {
        var revision = settings.accountSessionRevision
        isAuthenticating = true
        canCancelSignIn = true
        statusMessage = "Waiting for authentication in your browser…"
        errorMessage = nil
        remainingSeconds = nil

        let clientIdentifier = settings.clientIdentifier
        let clientContext = PlexClientContext(clientIdentifier: clientIdentifier)

        do {
            let identity = try await deviceIdentityStore.loadOrCreateIdentity()
            try requireCurrentSession(revision)
            let pin = try await client.createPin(
                jwk: identity.publicJWK(includeUse: false),
                clientContext: clientContext
            )
            try requireCurrentSession(revision)
            let deviceJWT = try identity.signedDeviceJWT(clientIdentifier: clientIdentifier)
            guard let authURL = clientContext.authURL(for: pin.code) else {
                throw PlexAuthError.invalidAuthURL
            }

            NSWorkspace.shared.open(authURL)

            for seconds in stride(from: 120, through: 1, by: -1) {
                remainingSeconds = seconds

                let currentPin = try await client.fetchPin(
                    id: String(pin.id),
                    deviceJWT: deviceJWT,
                    clientContext: clientContext
                )
                try requireCurrentSession(revision)
                if let authToken = currentPin.authToken?.nilIfBlank {
                    try Task.checkCancellation()
                    canCancelSignIn = false
                    statusMessage = "Completing sign in…"
                    remainingSeconds = nil
                    settings.clearAuthentication()
                    revision = settings.accountSessionRevision
                    authenticatedUser = nil
                    availableServers = []
                    connectionStore.updateAvailableServers([])
                    let preparedToken = try await accountJWTManager.acceptNewAccountToken(
                        authToken,
                        registeredKeyID: identity.keyID
                    )
                    try requireCurrentSession(revision)
                    scheduleAccountTokenRefresh(preparedToken)
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
            guard revision == settings.accountSessionRevision, !Task.isCancelled else { return }
            statusMessage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        remainingSeconds = nil
        isAuthenticating = false
        canCancelSignIn = false
    }

    private func clearSignInPresentation() {
        isAuthenticating = false
        canCancelSignIn = false
        statusMessage = nil
        errorMessage = nil
        remainingSeconds = nil
    }

    private func loadAuthenticatedUser() async {
        let revision = settings.accountSessionRevision
        isLoadingAuthenticatedUser = true
        accountErrorMessage = nil

        do {
            let user = try await performAccountRequest { token in
                try await client.fetchAuthenticatedUser(
                    userToken: token,
                    clientContext: PlexClientContext(clientIdentifier: settings.clientIdentifier)
                )
            }
            try requireCurrentSession(revision)
            authenticatedUser = user
            settings.recordVerifiedAccount(id: user.id)
        } catch {
            guard revision == settings.accountSessionRevision, !Task.isCancelled else { return }
            authenticatedUser = nil
            accountErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoadingAuthenticatedUser = false
    }

    private func loadServers(
        autoSelectStoredServer: Bool
    ) async {
        let revision = settings.accountSessionRevision
        isLoadingServers = true
        errorMessage = nil

        do {
            let servers = try await performAccountRequest { token in
                try await client.fetchServers(
                    userToken: token,
                    clientContext: PlexClientContext(clientIdentifier: settings.clientIdentifier)
                )
            }
            try requireCurrentSession(revision)
            guard !servers.isEmpty else {
                throw PlexAuthError.noServersFound
            }

            availableServers = servers
            connectionStore.updateAvailableServers(servers)

            if autoSelectStoredServer,
               let selectedServerIdentifier = settings.selectedServerIdentifier,
               let storedServer = servers.first(where: { $0.id == selectedServerIdentifier }) {
                selectServer(storedServer)
            } else if settings.selectedServerIdentifier == nil
                || !servers.contains(where: { $0.id == settings.selectedServerIdentifier }) {
                selectServer(servers[0])
            }

            statusMessage = nil
        } catch {
            guard revision == settings.accountSessionRevision, !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoadingServers = false
    }

}

private extension PlexAuthStore {
    func requireCurrentSession(_ revision: UUID) throws {
        try Task.checkCancellation()
        guard revision == settings.accountSessionRevision else { throw CancellationError() }
    }

    func performAccountRequest<Value>(
        _ operation: (String) async throws -> Value
    ) async throws -> Value {
        let revision = settings.accountSessionRevision
        let preparedToken = try await accountJWTManager.prepareAccountToken()
        try requireCurrentSession(revision)
        scheduleAccountTokenRefresh(preparedToken)

        do {
            let result = try await operation(preparedToken.token)
            try requireCurrentSession(revision)
            return result
        } catch let error as PlexAuthError where error.requiresTokenRefresh {
            try requireCurrentSession(revision)
            let refreshedToken = try await accountJWTManager.recoverRejectedAccountToken(preparedToken.token)
            try requireCurrentSession(revision)
            scheduleAccountTokenRefresh(refreshedToken)
            do {
                let result = try await operation(refreshedToken.token)
                try requireCurrentSession(revision)
                return result
            } catch let retryError as PlexAuthError where retryError.requiresTokenRefresh {
                try requireCurrentSession(revision)
                // A rejected old token must not clear a concurrently refreshed credential.
                if settings.trimmedUserToken == refreshedToken.token {
                    signOut()
                }
                throw retryError
            }
        }
    }

    func scheduleAccountTokenRefresh(_ preparedToken: PlexPreparedAccountToken) {
        let revision = settings.accountSessionRevision
        accountTokenRefreshTask?.cancel()
        let delay = max(preparedToken.refreshAt.timeIntervalSinceNow, 0)
        accountTokenRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else {
                return
            }

            do {
                let refreshedToken = try await accountJWTManager.prepareAccountToken(forceRefresh: true)
                try requireCurrentSession(revision)
                scheduleAccountTokenRefresh(refreshedToken)
                accountErrorMessage = nil
            } catch {
                guard revision == settings.accountSessionRevision, !Task.isCancelled else { return }
                accountErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
