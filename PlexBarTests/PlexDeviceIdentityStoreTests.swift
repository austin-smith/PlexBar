@testable import PlexClientKit
import Foundation
import Testing
@testable import PlexBar

private final class DeviceIdentityPersistenceStub: PlexDeviceIdentityPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private let discardedAccounts: Set<String>
    private var values: [String: String]

    init(
        values: [String: String] = [:],
        discardedAccounts: Set<String> = []
    ) {
        self.values = values
        self.discardedAccounts = discardedAccounts
    }

    func read(account: String) async -> String? {
        lock.withLock {
            values[account]
        }
    }

    func write(_ value: String, account: String) async {
        lock.withLock {
            guard !discardedAccounts.contains(account) else {
                return
            }
            values[account] = value
        }
    }

    func delete(account: String) async {
        lock.withLock {
            values[account] = nil
        }
    }

    func snapshot() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

struct PlexDeviceIdentityStoreTests {
    @Test func generatedIdentityIsPersistedAndReloadedExactly() async throws {
        let persistence = DeviceIdentityPersistenceStub()
        let store = PlexKeychainDeviceIdentityStore(keychain: persistence)

        let generated = try await store.loadOrCreateIdentity()
        let reloadedStore = PlexKeychainDeviceIdentityStore(keychain: persistence)
        let reloaded = try await reloadedStore.loadOrCreateIdentity()

        #expect(reloaded == generated)
        #expect(persistence.snapshot()[KeychainAccounts.jwtKeyID] == generated.keyID)
        #expect(
            persistence.snapshot()[KeychainAccounts.jwtPrivateKey]
                == generated.privateKeyRepresentation.base64EncodedString()
        )
    }

    @Test func incompletePersistedIdentityIsRejected() async {
        let persistence = DeviceIdentityPersistenceStub(values: [
            KeychainAccounts.jwtKeyID: "device-key",
        ])
        let store = PlexKeychainDeviceIdentityStore(keychain: persistence)

        await #expect(throws: PlexJWTError.self) {
            _ = try await store.loadOrCreateIdentity()
        }
    }

    @Test func failedPersistenceDeletesPartialIdentityAndSurfacesError() async {
        let persistence = DeviceIdentityPersistenceStub(
            discardedAccounts: [KeychainAccounts.jwtPrivateKey]
        )
        let store = PlexKeychainDeviceIdentityStore(keychain: persistence)

        await #expect(throws: PlexJWTError.self) {
            _ = try await store.loadOrCreateIdentity()
        }

        #expect(persistence.snapshot().isEmpty)
    }
}
