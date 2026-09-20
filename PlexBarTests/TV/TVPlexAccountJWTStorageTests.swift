#if os(tvOS)
import Foundation
import PlexClientKit
import Testing
@testable import PlexBarTV

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TVPlexAccountJWTStorageTests {
    @Test(arguments: [false, true], ["", "new-account-token"])
    func supersedingAuthenticationWinsOverAnInFlightWrite(cancelWrite: Bool, replacement: String) async throws {
        let suite = "TVPlexAccountJWTStorageTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = TVBlockingAccountCredentials()
        let storage = TVPlexAccountJWTStorage(defaults: defaults, credentialStore: credentials)
        try await storage.loadAccountToken()
        let oldRevision = storage.accountTokenRevision
        let oldWrite = Task {
            try await storage.persistAccountToken("refresh-token", expectedRevision: oldRevision)
        }
        await credentials.waitUntilBlocked()
        if cancelWrite { oldWrite.cancel() }
        let revision = storage.accountTokenRevision
        let replacementWrite = Task { try await storage.persistAccountToken(replacement) }
        while storage.accountTokenRevision == revision { await Task.yield() }
        if replacement.isEmpty { #expect(storage.storedAccountToken.isEmpty) }
        await credentials.release()
        await #expect(throws: CancellationError.self) { try await oldWrite.value }
        try await replacementWrite.value
        await #expect(throws: CancellationError.self) {
            try await storage.persistAccountToken("stale-token", expectedRevision: oldRevision)
        }
        #expect(storage.storedAccountToken == replacement)
        #expect(await credentials.loadCredentials().userToken == replacement)
    }

    @Test func signOutInvalidatesAPendingCredentialLoad() async throws {
        let suite = "TVPlexAccountJWTStorageTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = TVBlockingAccountCredentials(blockLoad: true)
        let storage = TVPlexAccountJWTStorage(defaults: defaults, credentialStore: credentials)
        let loading = Task { try await storage.loadAccountToken() }
        await credentials.waitUntilBlocked()
        try await storage.persistAccountToken("")
        await credentials.release()
        await #expect(throws: CancellationError.self) { try await loading.value }
        #expect(storage.storedAccountToken.isEmpty)
        #expect(await credentials.loadCredentials().userToken.isEmpty == true)
    }

    @Test func cancelledWriteWithoutNewerAuthenticationRestoresPriorToken() async throws {
        let suite = "TVPlexAccountJWTStorageTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = TVBlockingAccountCredentials()
        let storage = TVPlexAccountJWTStorage(defaults: defaults, credentialStore: credentials)
        try await storage.loadAccountToken()
        let write = Task { try await storage.persistAccountToken("refresh-token") }
        await credentials.waitUntilBlocked()
        write.cancel()
        await credentials.release()
        await #expect(throws: CancellationError.self) { try await write.value }
        #expect(storage.storedAccountToken == "prior-token")
        #expect(await credentials.loadCredentials().userToken == "prior-token")
    }
}

private actor TVBlockingAccountCredentials: PlexCredentialPersisting {
    private var token = "prior-token"
    private var shouldBlock: Bool
    private var blockLoad: Bool
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(blockLoad: Bool = false) {
        self.blockLoad = blockLoad
        shouldBlock = !blockLoad
    }

    func loadCredentials() async -> PlexStoredCredentials {
        let capturedToken = token
        if blockLoad {
            blockLoad = false
            await block()
        }
        return PlexStoredCredentials(userToken: capturedToken, serverToken: "")
    }

    func replace(_ value: String?, account: String) async {
        if shouldBlock {
            shouldBlock = false
            await block()
        }
        token = value ?? ""
    }

    private func block() async {
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
            entered = true
            entryWaiter?.resume()
            entryWaiter = nil
        }
    }

    func waitUntilBlocked() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
#endif
