import Foundation
import Testing
@testable import PlexBar

private enum JWTClientCall: Equatable, Sendable {
    case registerJWK(legacyToken: String, use: String?, clientIdentifier: String)
    case fetchNonce(clientIdentifier: String)
    case exchange(deviceJWT: String, clientIdentifier: String)
}

private struct JWTClientTestError: Error {}

private struct JWTCredentialPersistenceTestError: Error {}

private actor RejectingJWTCredentialStore: PlexCredentialPersisting {
    func loadCredentials() -> PlexStoredCredentials {
        .empty
    }

    func replace(_ value: String?, account: String) throws {
        throw JWTCredentialPersistenceTestError()
    }
}

private actor RecordingAccountJWTClient: PlexAccountJWTClient {
    private let nonce: String
    private let exchangedToken: String
    private let registerError: Error?
    private let exchangeError: Error?
    private var calls: [JWTClientCall] = []

    init(
        nonce: String = "test-nonce",
        exchangedToken: String,
        registerError: Error? = nil,
        exchangeError: Error? = nil
    ) {
        self.nonce = nonce
        self.exchangedToken = exchangedToken
        self.registerError = registerError
        self.exchangeError = exchangeError
    }

    func registerJWK(
        _ jwk: PlexJSONWebKey,
        legacyToken: String,
        clientContext: PlexClientContext
    ) throws {
        calls.append(.registerJWK(
            legacyToken: legacyToken,
            use: jwk.use,
            clientIdentifier: clientContext.clientIdentifier
        ))
        if let registerError {
            throw registerError
        }
    }

    func fetchJWTNonce(clientContext: PlexClientContext) throws -> String {
        calls.append(.fetchNonce(clientIdentifier: clientContext.clientIdentifier))
        return nonce
    }

    func exchangeDeviceJWT(
        _ deviceJWT: String,
        clientContext: PlexClientContext
    ) throws -> String {
        calls.append(.exchange(
            deviceJWT: deviceJWT,
            clientIdentifier: clientContext.clientIdentifier
        ))
        if let exchangeError {
            throw exchangeError
        }
        return exchangedToken
    }

    func recordedCalls() -> [JWTClientCall] {
        calls
    }
}

@MainActor
struct PlexAccountJWTManagerTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func migratesLegacyTokenAndPersistsRegistrationCheckpoint() async throws {
        let testState = try makeSettings(token: "legacy-account-token")
        defer { testState.cleanup() }
        let issuedToken = try accountJWT(expiration: now.addingTimeInterval(7 * 24 * 60 * 60))
        let client = RecordingAccountJWTClient(exchangedToken: issuedToken)
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "device-key")
        let manager = makeManager(settings: testState.store, client: client, identity: identity)

        let preparedToken = try await manager.prepareAccountToken()

        #expect(preparedToken.token == issuedToken)
        #expect(preparedToken.refreshAt == preparedToken.expiresAt.addingTimeInterval(-24 * 60 * 60))
        #expect(testState.store.userToken == issuedToken)
        #expect(testState.store.registeredJWTKeyID == "device-key")
        let calls = await client.recordedCalls()
        #expect(calls.count == 3)
        #expect(calls[0] == .registerJWK(
            legacyToken: "legacy-account-token",
            use: "sig",
            clientIdentifier: testState.store.clientIdentifier
        ))
        #expect(calls[1] == .fetchNonce(clientIdentifier: testState.store.clientIdentifier))
        guard case .exchange(let deviceJWT, let clientIdentifier) = calls[2] else {
            Issue.record("Expected device JWT exchange")
            return
        }
        #expect(clientIdentifier == testState.store.clientIdentifier)
        #expect(deviceJWT.split(separator: ".").count == 3)

        let reloadedStore = PlexSettingsStore(
            defaults: testState.defaults,
            initialCredentials: PlexStoredCredentials(userToken: issuedToken, serverToken: "")
        )
        #expect(reloadedStore.registeredJWTKeyID == "device-key")
    }

    @Test func failedExchangeKeepsLegacyTokenButPersistsRegistration() async throws {
        let testState = try makeSettings(token: "legacy-account-token")
        defer { testState.cleanup() }
        let fallbackToken = try accountJWT(expiration: now.addingTimeInterval(7 * 24 * 60 * 60))
        let client = RecordingAccountJWTClient(
            exchangedToken: fallbackToken,
            exchangeError: JWTClientTestError()
        )
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "device-key")
        let manager = makeManager(settings: testState.store, client: client, identity: identity)

        await #expect(throws: JWTClientTestError.self) {
            _ = try await manager.prepareAccountToken()
        }

        #expect(testState.store.registeredJWTKeyID == "device-key")
        #expect(testState.store.userToken == "legacy-account-token")
        #expect(await client.recordedCalls().count == 3)
    }

    @Test func failedRegistrationKeepsLegacyTokenAndDoesNotPersistCheckpoint() async throws {
        let testState = try makeSettings(token: "legacy-account-token")
        defer { testState.cleanup() }
        let issuedToken = try accountJWT(expiration: now.addingTimeInterval(7 * 24 * 60 * 60))
        let client = RecordingAccountJWTClient(
            exchangedToken: issuedToken,
            registerError: JWTClientTestError()
        )
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "device-key")
        let manager = makeManager(settings: testState.store, client: client, identity: identity)

        await #expect(throws: JWTClientTestError.self) {
            _ = try await manager.prepareAccountToken()
        }

        #expect(testState.store.registeredJWTKeyID == nil)
        #expect(testState.store.userToken == "legacy-account-token")
        #expect(await client.recordedCalls() == [
            .registerJWK(
                legacyToken: "legacy-account-token",
                use: "sig",
                clientIdentifier: testState.store.clientIdentifier
            ),
        ])
    }

    @Test func resumesRegisteredLegacyMigrationWithoutRegisteringAgain() async throws {
        let testState = try makeSettings(token: "legacy-account-token")
        defer { testState.cleanup() }
        testState.store.markJWTKeyRegistered(keyID: "device-key")
        let issuedToken = try accountJWT(expiration: now.addingTimeInterval(7 * 24 * 60 * 60))
        let client = RecordingAccountJWTClient(exchangedToken: issuedToken)
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "device-key")
        let manager = makeManager(settings: testState.store, client: client, identity: identity)

        _ = try await manager.prepareAccountToken()

        let calls = await client.recordedCalls()
        #expect(calls.count == 2)
        #expect(calls[0] == .fetchNonce(clientIdentifier: testState.store.clientIdentifier))
        guard case .exchange = calls[1] else {
            Issue.record("Expected device JWT exchange")
            return
        }
    }

    @Test func registersAgainWhenCheckpointBelongsToDifferentKey() async throws {
        let testState = try makeSettings(token: "legacy-account-token")
        defer { testState.cleanup() }
        testState.store.markJWTKeyRegistered(keyID: "old-device-key")
        let issuedToken = try accountJWT(expiration: now.addingTimeInterval(7 * 24 * 60 * 60))
        let client = RecordingAccountJWTClient(exchangedToken: issuedToken)
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "new-device-key")
        let manager = makeManager(settings: testState.store, client: client, identity: identity)

        _ = try await manager.prepareAccountToken()

        #expect(testState.store.registeredJWTKeyID == "new-device-key")
        let calls = await client.recordedCalls()
        #expect(calls.count == 3)
        #expect(calls[0] == .registerJWK(
            legacyToken: "legacy-account-token",
            use: "sig",
            clientIdentifier: testState.store.clientIdentifier
        ))
    }

    @Test func reusesJWTOutsideRefreshWindowWithoutNetworkWork() async throws {
        let storedToken = try accountJWT(expiration: now.addingTimeInterval(3 * 24 * 60 * 60))
        let testState = try makeSettings(token: storedToken)
        defer { testState.cleanup() }
        let client = RecordingAccountJWTClient(exchangedToken: storedToken)
        let manager = makeManager(settings: testState.store, client: client)

        let preparedToken = try await manager.prepareAccountToken()

        #expect(preparedToken.token == storedToken)
        #expect(testState.store.registeredJWTKeyID == nil)
        #expect(await client.recordedCalls().isEmpty)
    }

    @Test func refreshesFutureDatedJWTAfterPlexRejectsIt() async throws {
        let rejectedToken = try accountJWT(expiration: now.addingTimeInterval(3 * 24 * 60 * 60))
        let issuedToken = try accountJWT(expiration: now.addingTimeInterval(7 * 24 * 60 * 60))
        let testState = try makeSettings(token: rejectedToken)
        defer { testState.cleanup() }
        let client = RecordingAccountJWTClient(exchangedToken: issuedToken)
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "device-key")
        let manager = makeManager(settings: testState.store, client: client, identity: identity)

        let preparedToken = try await manager.recoverRejectedAccountToken(rejectedToken)

        #expect(preparedToken.token == issuedToken)
        #expect(testState.store.userToken == issuedToken)
        #expect(await client.recordedCalls().count == 2)
    }

    @Test func refreshesJWTInsideRefreshWindow() async throws {
        let storedToken = try accountJWT(expiration: now.addingTimeInterval(60 * 60))
        let issuedToken = try accountJWT(expiration: now.addingTimeInterval(7 * 24 * 60 * 60))
        let testState = try makeSettings(token: storedToken)
        defer { testState.cleanup() }
        let client = RecordingAccountJWTClient(exchangedToken: issuedToken)
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "device-key")
        let manager = makeManager(settings: testState.store, client: client, identity: identity)

        let preparedToken = try await manager.prepareAccountToken()

        #expect(preparedToken.token == issuedToken)
        #expect(testState.store.registeredJWTKeyID == "device-key")
        let calls = await client.recordedCalls()
        #expect(calls.count == 2)
        #expect(calls[0] == .fetchNonce(clientIdentifier: testState.store.clientIdentifier))
        guard case .exchange = calls[1] else {
            Issue.record("Expected device JWT exchange")
            return
        }
    }

    @Test func refreshesExpiredJWTBeforeReturningItForAccountRequests() async throws {
        let expiredToken = try accountJWT(expiration: now.addingTimeInterval(-60))
        let issuedToken = try accountJWT(expiration: now.addingTimeInterval(7 * 24 * 60 * 60))
        let testState = try makeSettings(token: expiredToken)
        defer { testState.cleanup() }
        let client = RecordingAccountJWTClient(exchangedToken: issuedToken)
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "device-key")
        let manager = makeManager(settings: testState.store, client: client, identity: identity)

        let preparedToken = try await manager.prepareAccountToken()

        #expect(preparedToken.token == issuedToken)
        #expect(testState.store.userToken == issuedToken)
        #expect(await client.recordedCalls().count == 2)
    }

    @Test func accountTokenMigrationPreservesResourceServerToken() async throws {
        let testState = try makeSettings(
            token: "legacy-account-token",
            serverToken: "resource-server-token"
        )
        defer { testState.cleanup() }
        let issuedToken = try accountJWT(expiration: now.addingTimeInterval(7 * 24 * 60 * 60))
        let client = RecordingAccountJWTClient(exchangedToken: issuedToken)
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "device-key")
        let manager = makeManager(settings: testState.store, client: client, identity: identity)

        _ = try await manager.prepareAccountToken()

        #expect(testState.store.userToken == issuedToken)
        #expect(testState.store.serverToken == "resource-server-token")
    }

    @Test func acceptsPinIssuedJWTWithItsRegisteredKeyIdentity() async throws {
        let testState = try makeSettings(token: "")
        defer { testState.cleanup() }
        let issuedToken = try accountJWT(expiration: now.addingTimeInterval(7 * 24 * 60 * 60))
        let client = RecordingAccountJWTClient(exchangedToken: issuedToken)
        let manager = makeManager(settings: testState.store, client: client)

        let preparedToken = try await manager.acceptNewAccountToken(
            issuedToken,
            registeredKeyID: "pin-device-key"
        )

        #expect(preparedToken.token == issuedToken)
        #expect(testState.store.userToken == issuedToken)
        #expect(testState.store.registeredJWTKeyID == "pin-device-key")
    }

    @Test func pinIssuedJWTIsNotPublishedWhenDurablePersistenceFails() async throws {
        let suiteName = "PlexBarTests.PlexAccountJWTManager.persistenceFailure.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: RejectingJWTCredentialStore(),
            initialCredentials: .empty
        )
        let issuedToken = try accountJWT(expiration: now.addingTimeInterval(7 * 24 * 60 * 60))
        let manager = makeManager(
            settings: settings,
            client: RecordingAccountJWTClient(exchangedToken: issuedToken)
        )

        await #expect(throws: JWTCredentialPersistenceTestError.self) {
            _ = try await manager.acceptNewAccountToken(
                issuedToken,
                registeredKeyID: "pin-device-key"
            )
        }

        #expect(settings.userToken.isEmpty)
        #expect(!settings.hasAuthenticatedAccount)
        #expect(settings.registeredJWTKeyID == "pin-device-key")
    }

    @Test func rejectsLegacyTokenReturnedByExchange() async throws {
        let testState = try makeSettings(token: "legacy-account-token")
        defer { testState.cleanup() }
        let client = RecordingAccountJWTClient(exchangedToken: "another-legacy-token")
        let manager = makeManager(settings: testState.store, client: client)

        await #expect(throws: PlexJWTError.self) {
            _ = try await manager.prepareAccountToken()
        }

        #expect(testState.store.userToken == "legacy-account-token")
    }

    @Test func rejectsIssuedJWTThatWouldImmediatelyNeedRefresh() async throws {
        let testState = try makeSettings(token: "legacy-account-token")
        defer { testState.cleanup() }
        let shortToken = try accountJWT(expiration: now.addingTimeInterval(60 * 60))
        let client = RecordingAccountJWTClient(exchangedToken: shortToken)
        let manager = makeManager(settings: testState.store, client: client)

        await #expect(throws: PlexJWTError.self) {
            _ = try await manager.prepareAccountToken()
        }

        #expect(testState.store.userToken == "legacy-account-token")
    }

    private func makeManager(
        settings: PlexSettingsStore,
        client: RecordingAccountJWTClient,
        identity: PlexDeviceSigningIdentity? = nil
    ) -> PlexAccountJWTManager {
        PlexAccountJWTManager(
            settings: settings,
            client: client,
            deviceIdentityStore: PlexMemoryDeviceIdentityStore(identity: identity),
            now: { now }
        )
    }

    private func makeSettings(
        token: String,
        serverToken: String = ""
    ) throws -> JWTManagerTestState {
        let suiteName = "PlexBarTests.PlexAccountJWTManager.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return JWTManagerTestState(
            store: PlexSettingsStore(
                defaults: defaults,
                credentialStore: PlexMemoryCredentialStore(credentials: PlexStoredCredentials(
                    userToken: token,
                    serverToken: serverToken
                )),
                initialCredentials: PlexStoredCredentials(
                    userToken: token,
                    serverToken: serverToken
                )
            ),
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func accountJWT(expiration: Date) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "EdDSA"])
        let payload = try JSONSerialization.data(withJSONObject: ["exp": Int(expiration.timeIntervalSince1970)])
        return "\(base64URL(header)).\(base64URL(payload)).test-signature"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

@MainActor
private struct JWTManagerTestState {
    let store: PlexSettingsStore
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
