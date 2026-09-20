import Foundation

public struct PlexPreparedAccountToken: Equatable, Sendable {
    public let token: String
    public let expiresAt: Date
    public let refreshAt: Date

    public init(token: String, expiresAt: Date, refreshAt: Date) {
        self.token = token
        self.expiresAt = expiresAt
        self.refreshAt = refreshAt
    }
}

@MainActor
public protocol PlexAccountJWTStorage: AnyObject {
    var clientIdentifier: String { get }
    var storedAccountToken: String { get }
    /// Changes synchronously when credentials are replaced or cleared, before any storage await.
    var accountTokenRevision: UUID { get }
    var registeredJWTKeyID: String? { get }

    /// Reject stale revisions and prevent superseded writes from publishing or rolling back credentials.
    func persistAccountToken(_ token: String, expectedRevision: UUID) async throws
    func markJWTKeyRegistered(keyID: String)
}

@MainActor
public final class PlexAccountJWTManager {
    public nonisolated static let requestedScope = "username,email,friendly_name"
    public nonisolated static let defaultRefreshLeadTime: TimeInterval = 24 * 60 * 60

    private let makeClientContext: @Sendable (String) -> PlexClientContext
    private let storage: any PlexAccountJWTStorage
    private let client: any PlexAccountJWTClient
    private let deviceIdentityStore: any PlexDeviceIdentityProviding
    private let refreshLeadTime: TimeInterval
    private let now: @Sendable () -> Date
    private var preparationTask: Task<PlexPreparedAccountToken, Error>?
    private var preparationID = UUID()

    public init(
        storage: any PlexAccountJWTStorage,
        clientContext: @escaping @Sendable (String) -> PlexClientContext,
        client: any PlexAccountJWTClient,
        deviceIdentityStore: any PlexDeviceIdentityProviding,
        refreshLeadTime: TimeInterval = PlexAccountJWTManager.defaultRefreshLeadTime,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.makeClientContext = clientContext
        self.storage = storage
        self.client = client
        self.deviceIdentityStore = deviceIdentityStore
        self.refreshLeadTime = refreshLeadTime
        self.now = now
    }

    public func prepareAccountToken(forceRefresh: Bool = false) async throws -> PlexPreparedAccountToken {
        try Task.checkCancellation()
        let revision = storage.accountTokenRevision
        if let preparationTask {
            let id = preparationID
            let prepared = try await preparationTask.value
            try Task.checkCancellation()
            guard preparationID == id else { throw CancellationError() }
            return prepared
        }

        return try await runPreparation {
            try await self.prepareAccountTokenNow(forceRefresh: forceRefresh, revision: revision)
        }
    }

    private func runPreparation(
        _ operation: @escaping @MainActor () async throws -> PlexPreparedAccountToken
    ) async throws -> PlexPreparedAccountToken {
        let id = UUID()
        preparationID = id
        let task = Task { @MainActor in try await operation() }
        preparationTask = task
        defer {
            if preparationID == id {
                preparationTask = nil
            }
        }
        let prepared = try await task.value
        try Task.checkCancellation()
        guard preparationID == id else { throw CancellationError() }
        return prepared
    }

    public func invalidatePreparation() {
        preparationTask?.cancel()
        preparationTask = nil
        preparationID = UUID()
    }

    public func acceptNewAccountToken(
        _ token: String,
        registeredKeyID: String
    ) async throws -> PlexPreparedAccountToken {
        try Task.checkCancellation()
        let preparedToken = try validateIssuedJWT(token, issuedAt: now())
        invalidatePreparation()
        let revision = storage.accountTokenRevision
        return try await runPreparation {
            try self.checkRevision(revision)
            self.storage.markJWTKeyRegistered(keyID: registeredKeyID)
            try await self.storage.persistAccountToken(preparedToken.token, expectedRevision: revision)
            return preparedToken
        }
    }

    public func recoverRejectedAccountToken(_ rejectedToken: String) async throws -> PlexPreparedAccountToken {
        if storage.storedAccountToken != rejectedToken {
            return try await prepareAccountToken()
        }

        return try await prepareAccountToken(forceRefresh: true)
    }

    private func prepareAccountTokenNow(forceRefresh: Bool, revision: UUID) async throws -> PlexPreparedAccountToken {
        try checkRevision(revision)
        let storedToken = storage.storedAccountToken
        guard !storedToken.isEmpty else {
            throw PlexJWTError.missingAccountToken
        }

        let currentDate = now()
        switch try PlexAccountToken(token: storedToken) {
        case .legacy:
            let identity = try await deviceIdentityStore.loadOrCreateIdentity()
            try checkRevision(revision)
            if storage.registeredJWTKeyID != identity.keyID {
                try await client.registerJWK(
                    identity.publicJWK(includeUse: true),
                    legacyToken: storedToken,
                    clientContext: clientContext
                )
                try checkRevision(revision)
                storage.markJWTKeyRegistered(keyID: identity.keyID)
            }
            return try await issueAccountToken(identity: identity, issuedAt: currentDate, revision: revision)

        case .jwt(let expiresAt):
            if !forceRefresh,
               expiresAt.timeIntervalSince(currentDate) > refreshLeadTime {
                return preparedToken(token: storedToken, expiresAt: expiresAt)
            }

            let identity = try await deviceIdentityStore.loadOrCreateIdentity()
            try checkRevision(revision)
            return try await issueAccountToken(identity: identity, issuedAt: currentDate, revision: revision)
        }
    }

    private func issueAccountToken(
        identity: PlexDeviceSigningIdentity,
        issuedAt: Date,
        revision: UUID
    ) async throws -> PlexPreparedAccountToken {
        let nonce = try await client.fetchJWTNonce(clientContext: clientContext)
        try checkRevision(revision)
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
        try checkRevision(revision)
        let preparedToken = try validateIssuedJWT(accountToken, issuedAt: issuedAt)
        storage.markJWTKeyRegistered(keyID: identity.keyID)
        try await storage.persistAccountToken(preparedToken.token, expectedRevision: revision)
        return preparedToken
    }

    private func checkRevision(_ revision: UUID) throws {
        try Task.checkCancellation()
        guard storage.accountTokenRevision == revision else { throw CancellationError() }
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
        makeClientContext(storage.clientIdentifier)
    }
}
