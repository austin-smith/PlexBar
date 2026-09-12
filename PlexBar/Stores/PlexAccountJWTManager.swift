import Foundation

struct PlexPreparedAccountToken: Equatable, Sendable {
    let token: String
    let expiresAt: Date
    let refreshAt: Date
}

@MainActor
protocol PlexAccountJWTStorage: AnyObject {
    var clientIdentifier: String { get }
    var storedAccountToken: String { get }
    var registeredJWTKeyID: String? { get }

    func persistAccountToken(_ token: String) async throws
    func markJWTKeyRegistered(keyID: String)
}

@MainActor
final class PlexAccountJWTManager {
    nonisolated static let requestedScope = "username,email,friendly_name"
    nonisolated static let defaultRefreshLeadTime: TimeInterval = 24 * 60 * 60

    private let storage: any PlexAccountJWTStorage
    private let client: any PlexAccountJWTClient
    private let deviceIdentityStore: any PlexDeviceIdentityProviding
    private let refreshLeadTime: TimeInterval
    private let now: @Sendable () -> Date
    private var preparationTask: Task<PlexPreparedAccountToken, Error>?

    init(
        storage: any PlexAccountJWTStorage,
        client: any PlexAccountJWTClient,
        deviceIdentityStore: any PlexDeviceIdentityProviding,
        refreshLeadTime: TimeInterval = PlexAccountJWTManager.defaultRefreshLeadTime,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.client = client
        self.deviceIdentityStore = deviceIdentityStore
        self.refreshLeadTime = refreshLeadTime
        self.now = now
    }

    func prepareAccountToken(forceRefresh: Bool = false) async throws -> PlexPreparedAccountToken {
        if let preparationTask {
            return try await preparationTask.value
        }

        let task = Task { @MainActor in
            try await prepareAccountTokenNow(forceRefresh: forceRefresh)
        }
        preparationTask = task
        defer { preparationTask = nil }
        return try await task.value
    }

    func acceptNewAccountToken(
        _ token: String,
        registeredKeyID: String
    ) async throws -> PlexPreparedAccountToken {
        preparationTask?.cancel()
        preparationTask = nil
        let preparedToken = try validateIssuedJWT(token, issuedAt: now())
        storage.markJWTKeyRegistered(keyID: registeredKeyID)
        try await storage.persistAccountToken(preparedToken.token)
        return preparedToken
    }

    func recoverRejectedAccountToken(_ rejectedToken: String) async throws -> PlexPreparedAccountToken {
        if storage.storedAccountToken != rejectedToken {
            return try await prepareAccountToken()
        }

        return try await prepareAccountToken(forceRefresh: true)
    }

    private func prepareAccountTokenNow(forceRefresh: Bool) async throws -> PlexPreparedAccountToken {
        let storedToken = storage.storedAccountToken
        guard !storedToken.isEmpty else {
            throw PlexJWTError.missingAccountToken
        }

        let currentDate = now()
        switch try PlexAccountToken(token: storedToken) {
        case .legacy:
            let identity = try await deviceIdentityStore.loadOrCreateIdentity()
            if storage.registeredJWTKeyID != identity.keyID {
                try await client.registerJWK(
                    identity.publicJWK(includeUse: true),
                    legacyToken: storedToken,
                    clientContext: clientContext
                )
                storage.markJWTKeyRegistered(keyID: identity.keyID)
            }
            return try await issueAccountToken(identity: identity, issuedAt: currentDate)

        case .jwt(let expiresAt):
            if !forceRefresh,
               expiresAt.timeIntervalSince(currentDate) > refreshLeadTime {
                return preparedToken(token: storedToken, expiresAt: expiresAt)
            }

            let identity = try await deviceIdentityStore.loadOrCreateIdentity()
            return try await issueAccountToken(identity: identity, issuedAt: currentDate)
        }
    }

    private func issueAccountToken(
        identity: PlexDeviceSigningIdentity,
        issuedAt: Date
    ) async throws -> PlexPreparedAccountToken {
        let nonce = try await client.fetchJWTNonce(clientContext: clientContext)
        let deviceJWT = try identity.signedDeviceJWT(
            clientIdentifier: storage.clientIdentifier,
            nonce: nonce,
            scope: Self.requestedScope,
            issuedAt: issuedAt
        )
        let accountToken = try await client.exchangeDeviceJWT(
            deviceJWT,
            clientContext: clientContext
        )
        let preparedToken = try validateIssuedJWT(accountToken, issuedAt: issuedAt)
        storage.markJWTKeyRegistered(keyID: identity.keyID)
        try await storage.persistAccountToken(preparedToken.token)
        return preparedToken
    }

    private func validateIssuedJWT(
        _ token: String,
        issuedAt: Date
    ) throws -> PlexPreparedAccountToken {
        guard case .jwt(let expiresAt) = try PlexAccountToken(token: token) else {
            throw PlexJWTError.expectedAccountJWT
        }
        guard expiresAt.timeIntervalSince(issuedAt) > refreshLeadTime else {
            throw PlexJWTError.accountTokenExpiresTooSoon
        }
        return preparedToken(token: token, expiresAt: expiresAt)
    }

    private func preparedToken(token: String, expiresAt: Date) -> PlexPreparedAccountToken {
        PlexPreparedAccountToken(
            token: token,
            expiresAt: expiresAt,
            refreshAt: expiresAt.addingTimeInterval(-refreshLeadTime)
        )
    }

    private var clientContext: PlexClientContext {
        PlexClientContext(clientIdentifier: storage.clientIdentifier)
    }
}
