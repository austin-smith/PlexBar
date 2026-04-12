import Foundation
import Observation

@MainActor
@Observable
final class PlexSettingsStore {
    private enum DefaultsKeys {
        static let installIdentifier = "plex.installIdentifier"
        static let serverURL = "plex.serverURL"
        static let clientIdentifier = "plex.clientIdentifier"
        static let selectedServerIdentifier = "plex.selectedServerIdentifier"
        static let selectedServerName = "plex.selectedServerName"
        static let pollIntervalSeconds = "plex.pollIntervalSeconds"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    var serverURLString: String {
        didSet {
            defaults.set(serverURLString, forKey: DefaultsKeys.serverURL)
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

    var pollIntervalSeconds: Int {
        didSet {
            let normalizedValue = Self.normalizedPollIntervalSeconds(pollIntervalSeconds)
            if pollIntervalSeconds != normalizedValue {
                pollIntervalSeconds = normalizedValue
                return
            }

            defaults.set(normalizedValue, forKey: DefaultsKeys.pollIntervalSeconds)
        }
    }

    private(set) var clientIdentifier: String {
        didSet {
            defaults.set(clientIdentifier, forKey: DefaultsKeys.clientIdentifier)
        }
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore(service: AppConstants.bundleIdentifier)) {
        self.defaults = defaults
        self.keychain = keychain
        serverURLString = defaults.string(forKey: DefaultsKeys.serverURL) ?? ""

        let installIdentifier = Self.loadInstallIdentifier(from: defaults)
        clientIdentifier = Self.loadClientIdentifier(from: defaults, installIdentifier: installIdentifier)

        selectedServerIdentifier = defaults.string(forKey: DefaultsKeys.selectedServerIdentifier)
        selectedServerName = defaults.string(forKey: DefaultsKeys.selectedServerName)
        userToken = keychain.read(account: KeychainAccounts.userToken) ?? ""
        serverToken = keychain.read(account: KeychainAccounts.serverToken) ?? ""
        pollIntervalSeconds = Self.normalizedPollIntervalSeconds(
            defaults.object(forKey: DefaultsKeys.pollIntervalSeconds) as? Int ?? AppConstants.defaultPollIntervalSeconds
        )
    }

    var normalizedServerURL: URL? {
        PlexURLBuilder.normalizeServerURL(serverURLString)
    }

    var trimmedUserToken: String {
        userToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedServerToken: String {
        serverToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasValidConfiguration: Bool {
        normalizedServerURL != nil && !trimmedServerToken.isEmpty
    }

    var hasAuthenticatedAccount: Bool {
        !trimmedUserToken.isEmpty
    }

    var pollIntervalDuration: Duration {
        .seconds(pollIntervalSeconds)
    }

    func saveAuthenticatedUserToken(_ token: String) {
        userToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func saveServerSelection(_ server: PlexServerResource) {
        selectedServerIdentifier = server.id
        selectedServerName = server.name
        serverURLString = server.selectedURL?.absoluteString ?? ""
        serverToken = server.accessToken
    }

    func clearAuthentication() {
        selectedServerIdentifier = nil
        selectedServerName = nil
        serverURLString = ""
        userToken = ""
        serverToken = ""
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

    private static func normalizedPollIntervalSeconds(_ value: Int) -> Int {
        min(max(value, AppConstants.minimumPollIntervalSeconds), AppConstants.maximumPollIntervalSeconds)
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
