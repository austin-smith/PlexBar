import PlexModels
import Foundation

@MainActor
final class TVPlexAccountJWTStorage: PlexAccountJWTStorage {
    private enum DefaultsKey {
        static let clientIdentifier = "tv.plex.clientIdentifier"
        static let registeredJWTKeyID = "tv.plex.registeredJWTKeyID"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    let clientIdentifier: String
    private(set) var storedAccountToken = ""
    private(set) var registeredJWTKeyID: String?

    init(defaults: UserDefaults, keychain: KeychainStore) {
        self.defaults = defaults
        self.keychain = keychain

        if let identifier = defaults.string(forKey: DefaultsKey.clientIdentifier)?.nilIfBlank {
            clientIdentifier = identifier
        } else {
            let identifier = UUID().uuidString.lowercased()
            defaults.set(identifier, forKey: DefaultsKey.clientIdentifier)
            clientIdentifier = identifier
        }

        registeredJWTKeyID = defaults.string(
            forKey: DefaultsKey.registeredJWTKeyID
        )?.nilIfBlank
    }

    func loadAccountToken() async throws {
        storedAccountToken = try await keychain.read(account: KeychainAccounts.userToken) ?? ""
    }

    func persistAccountToken(_ token: String) async throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedToken.isEmpty {
            try await keychain.delete(account: KeychainAccounts.userToken)
        } else {
            try await keychain.write(normalizedToken, account: KeychainAccounts.userToken)
        }
        storedAccountToken = normalizedToken
    }

    func markJWTKeyRegistered(keyID: String) {
        guard let keyID = keyID.nilIfBlank,
              registeredJWTKeyID != keyID else {
            return
        }
        registeredJWTKeyID = keyID
        defaults.set(keyID, forKey: DefaultsKey.registeredJWTKeyID)
    }
}
