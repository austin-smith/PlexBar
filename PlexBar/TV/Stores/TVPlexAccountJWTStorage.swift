import PlexClientKit
import PlexModels
import Foundation

@MainActor
final class TVPlexAccountJWTStorage: PlexAccountJWTStorage {
    private enum DefaultsKey {
        static let clientIdentifier = "tv.plex.clientIdentifier"
        static let registeredJWTKeyID = "tv.plex.registeredJWTKeyID"
    }

    private let defaults: UserDefaults
    private let credentialStore: any PlexCredentialPersisting
    private var persistenceTask: Task<Void, Error>?
    private(set) var accountTokenRevision = UUID()

    let clientIdentifier: String
    private(set) var storedAccountToken = ""
    private(set) var registeredJWTKeyID: String?

    convenience init(defaults: UserDefaults, keychain: KeychainStore) {
        self.init(defaults: defaults, credentialStore: PlexKeychainCredentialStore(keychain: keychain))
    }

    init(defaults: UserDefaults, credentialStore: any PlexCredentialPersisting) {
        self.defaults = defaults
        self.credentialStore = credentialStore

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
        let revision = accountTokenRevision
        let credentials = try await credentialStore.loadCredentials()
        try Task.checkCancellation()
        guard accountTokenRevision == revision else { throw CancellationError() }
        storedAccountToken = credentials.userToken
    }

    func persistAccountToken(_ token: String, expectedRevision: UUID) async throws {
        guard accountTokenRevision == expectedRevision else { throw CancellationError() }
        try await persistAccountToken(token)
    }

    func persistAccountToken(_ token: String) async throws {
        try Task.checkCancellation()
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousToken = storedAccountToken
        let revision = UUID()
        accountTokenRevision = revision
        // Sign-out takes effect immediately, even while an older write is draining.
        if normalizedToken.isEmpty { storedAccountToken = "" }
        let task = enqueuePersistence(normalizedToken)
        try await task.value
        guard accountTokenRevision == revision else { throw CancellationError() }
        do {
            try Task.checkCancellation()
        } catch {
            // A superseding sign-out/login owns its write; only roll back our own revision.
            try await enqueuePersistence(previousToken).value
            throw error
        }
        storedAccountToken = normalizedToken
    }

    private func enqueuePersistence(_ token: String) -> Task<Void, Error> {
        let previousTask = persistenceTask
        let credentialStore = credentialStore
        let task = Task {
            _ = try? await previousTask?.value
            try await credentialStore.replace(token.nilIfBlank, account: KeychainAccounts.userToken)
        }
        persistenceTask = task
        return task
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
