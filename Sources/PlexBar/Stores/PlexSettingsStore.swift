import Foundation
import Observation

@MainActor
@Observable
final class PlexSettingsStore {
    private enum DefaultsKeys {
        static let installIdentifier = "plex.installIdentifier"
        static let cachedConnectionURL = "plex.serverURL"
        static let cachedConnectionKind = "plex.cachedConnectionKind"
        static let clientIdentifier = "plex.clientIdentifier"
        static let selectedServerIdentifier = "plex.selectedServerIdentifier"
        static let selectedServerName = "plex.selectedServerName"
        static let connectionRecheckIntervalSeconds = "plex.connectionRecheckIntervalSeconds"
        static let historyPollIntervalSeconds = "plex.historyPollIntervalSeconds"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let loginItemService: any PlexLoginItemControlling

    var cachedConnectionURLString: String {
        didSet {
            defaults.set(cachedConnectionURLString, forKey: DefaultsKeys.cachedConnectionURL)
        }
    }

    var cachedConnectionKind: PlexConnectionKind? {
        didSet {
            defaults.set(cachedConnectionKind?.rawValue, forKey: DefaultsKeys.cachedConnectionKind)
        }
    }

    var selectedServerIdentifier: String? {
        didSet {
            defaults.set(selectedServerIdentifier, forKey: DefaultsKeys.selectedServerIdentifier)
        }
    }

    var selectedServerName: String? {
        didSet {
            defaults.set(selectedServerName, forKey: DefaultsKeys.selectedServerName)
        }
    }

    var userToken: String {
        didSet {
            persistUserToken()
        }
    }

    var serverToken: String {
        didSet {
            persistServerToken()
        }
    }

    var connectionRecheckIntervalSeconds: Int {
        didSet {
            let normalizedValue = Self.normalizedConnectionRecheckIntervalSeconds(connectionRecheckIntervalSeconds)
            if connectionRecheckIntervalSeconds != normalizedValue {
                connectionRecheckIntervalSeconds = normalizedValue
                return
            }

            defaults.set(normalizedValue, forKey: DefaultsKeys.connectionRecheckIntervalSeconds)
        }
    }

    var historyPollIntervalSeconds: Int {
        didSet {
            let normalizedValue = Self.normalizedHistoryPollIntervalSeconds(historyPollIntervalSeconds)
            if historyPollIntervalSeconds != normalizedValue {
                historyPollIntervalSeconds = normalizedValue
                return
            }

            defaults.set(normalizedValue, forKey: DefaultsKeys.historyPollIntervalSeconds)
        }
    }

    private(set) var clientIdentifier: String {
        didSet {
            defaults.set(clientIdentifier, forKey: DefaultsKeys.clientIdentifier)
        }
    }

    private(set) var openAtLoginStatus: PlexLoginItemStatus
    var openAtLoginErrorMessage: String?

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore(service: AppConstants.bundleIdentifier),
        loginItemService: any PlexLoginItemControlling = PlexLoginItemService()
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.loginItemService = loginItemService
        cachedConnectionURLString = defaults.string(forKey: DefaultsKeys.cachedConnectionURL) ?? ""
        cachedConnectionKind = defaults.string(forKey: DefaultsKeys.cachedConnectionKind).flatMap(PlexConnectionKind.init(rawValue:))

        let installIdentifier = Self.loadInstallIdentifier(from: defaults)
        clientIdentifier = Self.loadClientIdentifier(from: defaults, installIdentifier: installIdentifier)

        selectedServerIdentifier = defaults.string(forKey: DefaultsKeys.selectedServerIdentifier)
        selectedServerName = defaults.string(forKey: DefaultsKeys.selectedServerName)
        userToken = keychain.read(account: KeychainAccounts.userToken) ?? ""
        serverToken = keychain.read(account: KeychainAccounts.serverToken) ?? ""
        connectionRecheckIntervalSeconds = Self.normalizedConnectionRecheckIntervalSeconds(
            defaults.object(forKey: DefaultsKeys.connectionRecheckIntervalSeconds) as? Int ?? AppConstants.defaultConnectionRecheckIntervalSeconds
        )
        historyPollIntervalSeconds = Self.normalizedHistoryPollIntervalSeconds(
            defaults.object(forKey: DefaultsKeys.historyPollIntervalSeconds) as? Int ?? AppConstants.defaultHistoryPollIntervalSeconds
        )
        openAtLoginStatus = loginItemService.status()
        openAtLoginErrorMessage = nil
    }

    var normalizedServerURL: URL? {
        PlexURLBuilder.normalizeServerURL(cachedConnectionURLString)
    }

    var trimmedUserToken: String {
        userToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedServerToken: String {
        serverToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasValidConfiguration: Bool {
        selectedServerIdentifier?.nilIfBlank != nil && !trimmedServerToken.isEmpty
    }

    var hasAuthenticatedAccount: Bool {
        !trimmedUserToken.isEmpty
    }

    var connectionRecheckIntervalDuration: Duration? {
        guard connectionRecheckIntervalSeconds > 0 else {
            return nil
        }

        return .seconds(connectionRecheckIntervalSeconds)
    }

    var historyPollIntervalDuration: Duration {
        return .seconds(historyPollIntervalSeconds)
    }

    var opensAtLogin: Bool {
        switch openAtLoginStatus {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        }
    }

    var openAtLoginRequiresApproval: Bool {
        openAtLoginStatus == .requiresApproval
    }

    func saveAuthenticatedUserToken(_ token: String) {
        userToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func saveServerSelection(_ server: PlexServerResource) {
        selectedServerIdentifier = server.id
        selectedServerName = server.name
        serverToken = server.accessToken
        clearCachedConnection()
    }

    func saveResolvedConnection(_ connection: PlexResolvedConnection) {
        cachedConnectionURLString = connection.url.absoluteString
        cachedConnectionKind = connection.kind
    }

    func clearCachedConnection() {
        cachedConnectionURLString = ""
        cachedConnectionKind = nil
    }

    func clearAuthentication() {
        selectedServerIdentifier = nil
        selectedServerName = nil
        clearCachedConnection()
        userToken = ""
        serverToken = ""
    }

    func refreshOpenAtLoginStatus() {
        openAtLoginStatus = loginItemService.status()
        openAtLoginErrorMessage = nil
    }

    func setOpenAtLogin(_ enabled: Bool) {
        openAtLoginErrorMessage = nil

        do {
            try loginItemService.setEnabled(enabled)
            refreshOpenAtLoginStatus()

            if enabled && openAtLoginStatus == .notFound {
                openAtLoginErrorMessage = "PlexBar could not register itself as a login item."
            }
        } catch {
            refreshOpenAtLoginStatus()
            openAtLoginErrorMessage = openAtLoginActionErrorMessage(for: enabled, error: error)
        }
    }

    func openLoginItemsSystemSettings() {
        loginItemService.openSystemSettingsLoginItems()
    }

    @discardableResult
    func rotateClientIdentifier() -> String {
        let newIdentifier = Self.newIdentifier()
        clientIdentifier = newIdentifier
        return newIdentifier
    }

    private func persistUserToken() {
        let trimmedToken = trimmedUserToken

        if trimmedToken.isEmpty {
            keychain.delete(account: KeychainAccounts.userToken)
            return
        }

        keychain.write(trimmedToken, account: KeychainAccounts.userToken)
    }

    private func persistServerToken() {
        let trimmedToken = trimmedServerToken

        if trimmedToken.isEmpty {
            keychain.delete(account: KeychainAccounts.serverToken)
            return
        }

        keychain.write(trimmedToken, account: KeychainAccounts.serverToken)
    }

    private func openAtLoginActionErrorMessage(for enabled: Bool, error: Error) -> String {
        let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

        if enabled {
            return "PlexBar could not enable Open at Login. \(description)"
        }

        return "PlexBar could not disable Open at Login. \(description)"
    }

    private static func normalizedConnectionRecheckIntervalSeconds(_ value: Int) -> Int {
        guard AppConstants.allowedConnectionRecheckIntervalSeconds.contains(value) else {
            return AppConstants.defaultConnectionRecheckIntervalSeconds
        }

        return value
    }

    private static func normalizedHistoryPollIntervalSeconds(_ value: Int) -> Int {
        guard AppConstants.allowedHistoryPollIntervalSeconds.contains(value) else {
            return AppConstants.defaultHistoryPollIntervalSeconds
        }

        return value
    }

    private static func loadInstallIdentifier(from defaults: UserDefaults) -> String {
        if let existingInstallIdentifier = defaults.string(forKey: DefaultsKeys.installIdentifier)?.nilIfBlank {
            return existingInstallIdentifier
        }

        let installIdentifier = defaults.string(forKey: DefaultsKeys.clientIdentifier)?.nilIfBlank ?? newIdentifier()
        defaults.set(installIdentifier, forKey: DefaultsKeys.installIdentifier)
        return installIdentifier
    }

    private static func loadClientIdentifier(from defaults: UserDefaults, installIdentifier: String) -> String {
        if let existingClientIdentifier = defaults.string(forKey: DefaultsKeys.clientIdentifier)?.nilIfBlank {
            return existingClientIdentifier
        }

        defaults.set(installIdentifier, forKey: DefaultsKeys.clientIdentifier)
        return installIdentifier
    }

    private static func newIdentifier() -> String {
        UUID().uuidString
    }
}
