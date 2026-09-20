import Foundation
import PlexClientKit
import PlexModels
import Synchronization
import Testing
@testable import PlexBar

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct PlexAccountSessionTests {
    @Test func completedDownloadsRemainPlayableAfterAnOfflineColdLaunch() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        await fixture.auth.refreshAuthenticatedUser()
        #expect(fixture.settings.verifiedAccountID == 9)
        let package = try await fixture.publishDownload()
        try await fixture.settings.waitForCredentialPersistence()

        await fixture.server.setOffline()
        let relaunched = fixture.makeStores(initialCredentials: nil)
        await relaunched.settings.loadCredentials()
        await relaunched.auth.credentialsDidLoad()
        #expect(relaunched.auth.authenticatedUser == nil)
        #expect(relaunched.settings.verifiedAccountID == 9)
        await relaunched.downloads.start()
        let media = try #require(relaunched.downloads.downloadedMedia.first)
        #expect(media.id == package.id)
        #expect(!relaunched.downloads.canCreateDownload(for: media.item, libraryID: "1"))
        let presentation = try await relaunched.downloads.playbackPresentation(for: media)
        #expect(presentation.plan.url == package.mediaURL)
        #expect(presentation.plan.url.isFileURL)

        relaunched.auth.signOut()
        await relaunched.downloads.reload()
        #expect(relaunched.downloads.downloadedMedia.isEmpty)
        #expect(relaunched.settings.verifiedAccountID == nil)
        await #expect(throws: PlexDownloadWorkflowError.self) {
            _ = try await relaunched.downloads.playbackPresentation(for: media)
        }
        #expect(FileManager.default.fileExists(atPath: package.mediaURL.path))
    }

    @Test func tokenRefreshPreservesOfflineOwnershipButReplacementDoesNot() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        await fixture.auth.refreshAuthenticatedUser()
        _ = try await fixture.publishDownload()
        let revision = fixture.settings.accountSessionRevision
        let refreshed = try token("refreshed")
        try await fixture.settings.persistAccountToken(refreshed, expectedRevision: fixture.settings.accountTokenRevision)
        #expect(fixture.settings.accountSessionRevision == revision)
        #expect(fixture.settings.verifiedAccountID == 9)
        let relaunched = fixture.makeStores(initialCredentials: nil)
        await relaunched.settings.loadCredentials()
        #expect(relaunched.settings.verifiedAccountID == 9)

        try await fixture.settings.saveAuthenticatedUserToken(token("new"))
        #expect(fixture.settings.accountSessionRevision != revision)
        #expect(fixture.settings.verifiedAccountID == nil)
        await fixture.auth.refreshAuthenticatedUser()
        #expect(fixture.settings.verifiedAccountID == 10)
        await fixture.downloads.reload()
        #expect(fixture.downloads.downloadedMedia.isEmpty)
    }

    @Test func cachedOwnershipCannotBeRestoredWithADifferentCredential() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        await fixture.auth.refreshAuthenticatedUser()
        let changed = fixture.makeStores(initialCredentials: PlexStoredCredentials(userToken: try token("new"), serverToken: "server-token"))
        #expect(changed.settings.verifiedAccountID == nil)
        await changed.downloads.start()
        #expect(changed.downloads.downloadedMedia.isEmpty)
    }

    @Test(arguments: ["/api/v2/resources", "/api/v2/user"], [200, 401, 500])
    func lateAccountResponseCannotUndoSignOut(path: String, status: Int) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let gate = AccountResponseGate()
        await fixture.server.hold(path, gate: gate, status: status)
        let old = Task {
            if path == "/api/v2/user" { await fixture.auth.refreshAuthenticatedUser() }
            else { await fixture.auth.refreshServers(autoSelectStoredServer: true) }
        }
        await gate.waitUntilEntered()
        fixture.auth.signOut()
        await gate.release()
        await old.value
        try await fixture.settings.waitForCredentialPersistence()
        #expect(fixture.auth.authenticatedUser == nil)
        #expect(fixture.auth.availableServers.isEmpty)
        #expect(fixture.auth.errorMessage == nil)
        #expect(fixture.auth.accountErrorMessage == nil)
        #expect(fixture.settings.verifiedAccountID == nil)
        #expect(fixture.settings.selectedServerIdentifier == nil)
        #expect(fixture.settings.serverToken.isEmpty)
        #expect(await fixture.credentials.loadCredentials().serverToken.isEmpty == true)
        #expect(await fixture.server.refreshRequests == 0)
    }

    @Test(arguments: ["/api/v2/resources", "/api/v2/user"], [200, 401, 500])
    func lateAccountResponseCannotReplaceANewerLogin(path: String, status: Int) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let gate = AccountResponseGate()
        await fixture.server.hold(path, gate: gate, status: status)
        let old = Task {
            if path == "/api/v2/user" { await fixture.auth.refreshAuthenticatedUser() }
            else { await fixture.auth.refreshServers(autoSelectStoredServer: true) }
        }
        await gate.waitUntilEntered()
        fixture.auth.signOut()
        try await fixture.settings.saveAuthenticatedUserToken(token("new"))
        await fixture.auth.refreshAuthenticatedUser()
        await fixture.auth.refreshServers()
        await gate.release()
        await old.value
        #expect(fixture.auth.authenticatedUser?.id == 10)
        #expect(fixture.settings.verifiedAccountID == 10)
        #expect(fixture.auth.availableServers.first?.accessToken == "server-token-10")
        #expect(fixture.settings.serverToken == "server-token-10")
        #expect(fixture.auth.errorMessage == nil)
        #expect(fixture.auth.accountErrorMessage == nil)
        #expect(await fixture.server.refreshRequests == 0)
    }

    private func token(_ signature: String) throws -> String { try Fixture.token(signature) }

    @MainActor
    private final class Fixture {
        let suite = "PlexAccountSessionTests.\(UUID())"
        let defaults: UserDefaults
        let root: URL
        let credentials: PlexMemoryCredentialStore
        let session: URLSession
        let server = AccountServer()
        var stores: Stores!
        var settings: PlexSettingsStore { stores.settings }
        var auth: PlexAuthStore { stores.auth }
        var downloads: PlexDownloadsStore { stores.downloads }

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            root = URL.temporaryDirectory.appending(path: suite)
            let initial = PlexStoredCredentials(userToken: try Self.token("old"), serverToken: "server-token")
            credentials = PlexMemoryCredentialStore(credentials: initial)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [AccountSessionProtocol.self]
            session = URLSession(configuration: config)
            let server = server
            AccountSessionProtocol.handler.withLock { $0 = { try await server.respond($0) } }
            stores = makeStores(initialCredentials: initial)
            settings.selectedServerIdentifier = "server-id"
        }

        static func token(_ signature: String) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: ["exp": Int(Date().addingTimeInterval(7 * 86_400).timeIntervalSince1970)])
            let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            return "eyJhbGciOiJFZERTQSJ9.\(payload).\(signature)"
        }

        func makeStores(initialCredentials: PlexStoredCredentials?) -> Stores {
            let settings = PlexSettingsStore(defaults: defaults, credentialStore: credentials, initialCredentials: initialCredentials)
            let connection = PlexConnectionStore(settings: settings)
            let client = PlexAPIClient(session: session)
            let library = PlexLibraryStore(connectionStore: connection, client: client)
            let browser = PlexBrowserStore(connectionStore: connection, client: client)
            let auth = PlexAuthStore(
                settings: settings, connectionStore: connection,
                sessionStore: PlexSessionStore(connectionStore: connection, client: client),
                historyStore: PlexHistoryStore(connectionStore: connection, libraryStore: library, client: client, startsPolling: false),
                libraryStore: library, client: PlexAuthClient(session: session),
                deviceIdentityStore: PlexMemoryDeviceIdentityStore()
            )
            let packages = PlexDownloadPackageStore(rootURL: root)
            let transfers = PlexDownloadTransferCoordinator.inert(rootURL: root, packageStore: packages)
            let creation = PlexDownloadCreationStore(authStore: auth, connectionStore: connection, libraryStore: library, browserStore: browser, transferCoordinator: transfers)
            let downloads = PlexDownloadsStore(
                authStore: auth, connectionStore: connection, browserStore: browser, client: client,
                creationStore: creation, transferCoordinator: transfers, packageStore: packages,
                jobRegistry: PlexDownloadJobRegistry(rootURL: root), playbackRegistry: PlexOfflinePlaybackRegistry(rootURL: root),
                preparedAssetStore: PlexDownloadPreparedAssetStore(rootURL: root), automaticRuleRegistry: PlexAutomaticDownloadRuleRegistry(rootURL: root)
            )
            return Stores(settings: settings, auth: auth, downloads: downloads)
        }

        func publishDownload() async throws -> PlexDownloadPackage {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appending(path: "download.tmp")
            try Data("local media".utf8).write(to: file)
            return try await PlexDownloadPackageStore(rootURL: root).publish(
                identity: PlexDownloadPackageIdentity(packageID: UUID(), accountID: 9, serverIdentifier: "server-id", queueID: 7, queueItemID: 11, metadataKey: "/library/metadata/42", ratingKey: "42"),
                title: "Episode", mediaType: "episode",
                decisionData: Data(#"{"MediaContainer":{"allowSync":"1","Metadata":[{"ratingKey":"42","key":"/library/metadata/42","title":"Episode","type":"episode","duration":1800000,"Media":[{"id":1,"container":"mp4","videoCodec":"h264","audioCodec":"aac","Part":[{"id":2,"key":"/library/parts/2/file.mp4","container":"mp4"}]}]}]}}"#.utf8),
                downloadedFileURL: file, mediaFileExtension: "mp4", contentType: "video/mp4"
            )
        }

        func close() {
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private struct Stores {
        let settings: PlexSettingsStore
        let auth: PlexAuthStore
        let downloads: PlexDownloadsStore
    }
}

private actor AccountResponseGate {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    func block() async {
        await withCheckedContinuation { pending = $0; entered = true; entry?.resume(); entry = nil }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entry = $0 } }
    }
    func release() { pending?.resume(); pending = nil }
}

private actor AccountServer {
    private var offline = false
    private var gates: [String: (AccountResponseGate, Int)] = [:]
    private(set) var refreshRequests = 0
    func setOffline() { offline = true }
    func hold(_ path: String, gate: AccountResponseGate, status: Int) { gates[path] = (gate, status) }
    func respond(_ request: URLRequest) async throws -> (Int, Data) {
        if offline { throw URLError(.notConnectedToInternet) }
        let path = request.url!.path
        let account = request.value(forHTTPHeaderField: "X-Plex-Token")?.hasSuffix(".new") == true ? 10 : 9
        var status = 200
        if let (gate, code) = gates.removeValue(forKey: path) { status = code; await gate.block() }
        let json: String
        switch path {
        case "/api/v2/user": json = #"{"id":\#(account),"username":"account-\#(account)"}"#
        case "/api/v2/resources": json = #"[{"name":"Server","clientIdentifier":"server-id","provides":"server","connections":[{"uri":"https://plex.test","local":true,"relay":false}]}]"#
        case "/api/v2/devices": json = #"[{"name":"Server","clientIdentifier":"server-id","provides":"server","token":"server-token-\#(account)","connections":[{"uri":"https://plex.test"}]}]"#
        case "/api/v2/auth/nonce", "/api/v2/auth/token": refreshRequests += 1; throw URLError(.unsupportedURL)
        default: throw URLError(.unsupportedURL)
        }
        return (status, Data(json.utf8))
    }
}

private final class AccountSessionProtocol: URLProtocol, @unchecked Sendable {
    static let handler = Mutex<(@Sendable (URLRequest) async throws -> (Int, Data))?>(nil)
    private let loadingTask = Mutex<Task<Void, Never>?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler.withLock({ $0 }) else { return }
        let work = Task { @Sendable [self, request = request] in
            do {
                let (status, data) = try await handler(request)
                guard !Task.isCancelled else { return }
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
        loadingTask.withLock { $0 = work }
    }
    override func stopLoading() { loadingTask.withLock { $0?.cancel() } }
}
