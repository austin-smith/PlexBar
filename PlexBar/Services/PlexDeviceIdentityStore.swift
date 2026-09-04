import Foundation

protocol PlexDeviceIdentityProviding: Actor {
    func loadOrCreateIdentity() async throws -> PlexDeviceSigningIdentity
}

protocol PlexDeviceIdentityPersisting: Sendable {
    func read(account: String) async throws -> String?
    func write(_ value: String, account: String) async throws
    func delete(account: String) async throws
}

extension KeychainStore: PlexDeviceIdentityPersisting {}

actor PlexKeychainDeviceIdentityStore: PlexDeviceIdentityProviding {
    private let keychain: any PlexDeviceIdentityPersisting

    init(
        keychain: any PlexDeviceIdentityPersisting = KeychainStore(
            service: AppConstants.bundleIdentifier
        )
    ) {
        self.keychain = keychain
    }

    func loadOrCreateIdentity() async throws -> PlexDeviceSigningIdentity {
        async let storedKeyIDValue = keychain.read(account: KeychainAccounts.jwtKeyID)
        async let storedPrivateKeyValue = keychain.read(account: KeychainAccounts.jwtPrivateKey)
        let storedIdentity = try await (storedKeyIDValue, storedPrivateKeyValue)
        let storedKeyID = storedIdentity.0?.nilIfBlank
        let storedPrivateKey = storedIdentity.1?.nilIfBlank

        switch (storedKeyID, storedPrivateKey) {
        case (.none, .none):
            let identity = try PlexDeviceSigningIdentity.generate()
            do {
                try await keychain.write(identity.keyID, account: KeychainAccounts.jwtKeyID)
                try await keychain.write(
                    identity.privateKeyRepresentation.base64EncodedString(),
                    account: KeychainAccounts.jwtPrivateKey
                )
                async let persistedKeyID = keychain.read(account: KeychainAccounts.jwtKeyID)
                async let persistedPrivateKey = keychain.read(
                    account: KeychainAccounts.jwtPrivateKey
                )
                let persistedIdentity = try await (persistedKeyID, persistedPrivateKey)
                guard persistedIdentity.0 == identity.keyID,
                      persistedIdentity.1
                        == identity.privateKeyRepresentation.base64EncodedString() else {
                    throw PlexJWTError.deviceIdentityPersistenceFailed
                }
            } catch {
                try? await keychain.delete(account: KeychainAccounts.jwtKeyID)
                try? await keychain.delete(account: KeychainAccounts.jwtPrivateKey)
                throw error
            }
            return identity
        case (.some(let keyID), .some(let encodedPrivateKey)):
            guard let privateKey = Data(base64Encoded: encodedPrivateKey) else {
                throw PlexJWTError.incompleteDeviceIdentity
            }
            return try PlexDeviceSigningIdentity(
                keyID: keyID,
                privateKeyRepresentation: privateKey
            )
        default:
            throw PlexJWTError.incompleteDeviceIdentity
        }
    }
}

actor PlexMemoryDeviceIdentityStore: PlexDeviceIdentityProviding {
    private var identity: PlexDeviceSigningIdentity?

    init(identity: PlexDeviceSigningIdentity? = nil) {
        self.identity = identity
    }

    func loadOrCreateIdentity() async throws -> PlexDeviceSigningIdentity {
        if let identity {
            return identity
        }
        let identity = try PlexDeviceSigningIdentity.generate()
        self.identity = identity
        return identity
    }
}
