import Foundation
import Observation

@MainActor
@Observable
final class PlexSettingsStore {
    private enum DefaultsKeys {
        static let serverURL = "plex.serverURL"
        static let clientIdentifier = "plex.clientIdentifier"
        static let selectedServerIdentifier = "plex.selectedServerIdentifier"
        static let selectedServerName = "plex.selectedServerName"
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

    let clientIdentifier: String

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore(service: AppConstants.bundleIdentifier)) {
        self.defaults = defaults
        self.keychain = keychain
        serverURLString = defaults.string(forKey: DefaultsKeys.serverURL) ?? ""

        if let existingClientIdentifier = defaults.string(forKey: DefaultsKeys.clientIdentifier), !existingClientIdentifier.isEmpty {
            clientIdentifier = existingClientIdentifier
        } else {
            let newIdentifier = UUID().uuidString
            defaults.set(newIdentifier, forKey: DefaultsKeys.clientIdentifier)
            clientIdentifier = newIdentifier
        }

        selectedServerIdentifier = defaults.string(forKey: DefaultsKeys.selectedServerIdentifier)
        selectedServerName = defaults.string(forKey: DefaultsKeys.selectedServerName)
        userToken = keychain.read(account: KeychainAccounts.userToken) ?? ""
        serverToken = keychain.read(account: KeychainAccounts.serverToken) ?? ""
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
}
