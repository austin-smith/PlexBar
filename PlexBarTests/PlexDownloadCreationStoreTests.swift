import PlexModels
import Foundation
import Testing
@testable import PlexBar

@MainActor
@Suite(.serialized)
struct PlexDownloadCreationStoreTests {
    @Test func currentExactAuthorizationSchedulesAndResumesTheTransfer() async throws {
        let fixture = try DownloadCreationFixture()
        defer { fixture.removeRoot() }

        let record = try await fixture.store.schedule(
            fixture.transferRequest(),
            forLibraryID: fixture.library.id,
            transferID: fixture.transferID,
            createdAt: Date(timeIntervalSince1970: 1_777_777_777)
        )

        #expect(record.id == fixture.transferID)
        #expect(record.packageIdentity.serverIdentifier == "server-id")
        #expect(fixture.transferHarness.createdTaskCount == 1)
        #expect(fixture.transferHarness.resumedTaskIdentifiers == [41])
    }

    @Test func creationBoundaryUsesDownloadDefaultsInsteadOfStreamingQuality() throws {
        let fixture = try DownloadCreationFixture()
        defer { fixture.removeRoot() }
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: Data(#"""
        {
          "ratingKey": "42",
          "key": "/library/metadata/42",
          "title": "Movie",
          "type": "movie",
          "Media": [{
            "videoCodec": "hevc",
            "audioCodec": "aac",
            "width": 3840,
            "height": 2160,
            "bitrate": 30000,
            "Part": [{"key": "/library/parts/7/file.mkv"}]
          }]
        }
        """#.utf8))

        fixture.settings.localVideoQuality = .original
        fixture.settings.remoteVideoQuality = .sd1500Kbps
        fixture.settings.downloadVideoQuality = .fullHD12Mbps
        let first = try fixture.store.decisionParameters(
            for: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
            sessionIdentifier: "download-session"
        )

        fixture.settings.localVideoQuality = .hd2Mbps
        fixture.settings.remoteVideoQuality = .fourK20Mbps
        let second = try fixture.store.decisionParameters(
            for: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
            sessionIdentifier: "download-session"
        )

        #expect(first == second)
        #expect(second.videoBitrate == 12_000)
        #expect(second.videoResolution == "1920x1080")
        #expect(second.allowsDirectPlay == false)
    }

    @Test func signOutAndAccountSwitchImmediatelyInvalidateAGrant() async throws {
        let fixture = try DownloadCreationFixture()
        defer { fixture.removeRoot() }
        let grant = try await fixture.store.authorization(forLibraryID: fixture.library.id)

        fixture.authStore.authenticatedUser = nil
        fixture.settings.clearAuthentication()
        #expect(!fixture.store.isCurrent(grant))
        await #expect(throws: PlexDownloadCreationAuthorizationError.authorizationExpired) {
            _ = try await fixture.store.schedule(
                fixture.transferRequest(),
                authorization: grant
            )
        }

        fixture.restoreCredentials()
        fixture.authStore.authenticatedUser = fixture.user(id: 99)
        #expect(!fixture.store.isCurrent(grant))
        #expect(fixture.transferHarness.createdTaskCount == 0)
    }

    @Test func serverConnectionAndLibraryPermissionChangesInvalidateAGrant() async throws {
        let fixture = try DownloadCreationFixture()
        defer { fixture.removeRoot() }
        let grant = try await fixture.store.authorization(forLibraryID: fixture.library.id)

        fixture.connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "different-server",
            url: try #require(URL(string: "https://other-plex.local:32400")),
            kind: .remote,
            validatedAt: Date()
        )
        fixture.settings.selectedServerIdentifier = "different-server"
        #expect(!fixture.store.isCurrent(grant))

        fixture.restoreServer()
        fixture.libraryStore.libraries = [fixture.library(allowSync: false)]
        #expect(!fixture.store.isCurrent(grant))
        #expect(fixture.transferHarness.createdTaskCount == 0)
    }

    @Test func everyAccountServerLibraryAndProviderGateIsRequired() async throws {
        let noPass = try DownloadCreationFixture(userHasPlexPass: false)
        defer { noPass.removeRoot() }
        await #expect(throws: PlexDownloadCreationAuthorizationError.accountNotEntitled) {
            _ = try await noPass.store.authorization(forLibraryID: noPass.library.id)
        }

        let serverDenied = try DownloadCreationFixture(serverAllowsSync: false)
        defer { serverDenied.removeRoot() }
        await #expect(throws: PlexDownloadCreationAuthorizationError.serverDisallowsDownloads) {
            _ = try await serverDenied.store.authorization(forLibraryID: serverDenied.library.id)
        }

        let libraryDenied = try DownloadCreationFixture(libraryAllowsSync: false)
        defer { libraryDenied.removeRoot() }
        await #expect(throws: PlexDownloadCreationAuthorizationError.libraryDisallowsDownloads) {
            _ = try await libraryDenied.store.authorization(forLibraryID: libraryDenied.library.id)
        }

        let providerDenied = try DownloadCreationFixture(providerSupportsDownloads: false)
        defer { providerDenied.removeRoot() }
        await #expect(throws: PlexDownloadCreationAuthorizationError.providerDisallowsDownloads) {
            _ = try await providerDenied.store.authorization(forLibraryID: providerDenied.library.id)
        }
    }

    @Test func currentAuthorizationReflectsEveryAdvertisedDownloadGate() async throws {
        let authorized = try DownloadCreationFixture()
        defer { authorized.removeRoot() }
        await authorized.browserStore.loadLibraryProviderCapabilities()
        #expect(authorized.store.isCurrentlyAuthorized(forLibraryID: authorized.library.id))

        let noPass = try DownloadCreationFixture(userHasPlexPass: false)
        defer { noPass.removeRoot() }
        await noPass.browserStore.loadLibraryProviderCapabilities()
        #expect(!noPass.store.isCurrentlyAuthorized(forLibraryID: noPass.library.id))

        let serverDenied = try DownloadCreationFixture(serverAllowsSync: false)
        defer { serverDenied.removeRoot() }
        await serverDenied.browserStore.loadLibraryProviderCapabilities()
        #expect(!serverDenied.store.isCurrentlyAuthorized(forLibraryID: serverDenied.library.id))

        let libraryDenied = try DownloadCreationFixture(libraryAllowsSync: false)
        defer { libraryDenied.removeRoot() }
        await libraryDenied.browserStore.loadLibraryProviderCapabilities()
        #expect(!libraryDenied.store.isCurrentlyAuthorized(forLibraryID: libraryDenied.library.id))

        let providerDenied = try DownloadCreationFixture(providerSupportsDownloads: false)
        defer { providerDenied.removeRoot() }
        await providerDenied.browserStore.loadLibraryProviderCapabilities()
        #expect(!providerDenied.store.isCurrentlyAuthorized(forLibraryID: providerDenied.library.id))
    }

    @Test func transferMustMatchTheAuthorizedServerOriginLibraryAndQueueIdentity() async throws {
        let fixture = try DownloadCreationFixture()
        defer { fixture.removeRoot() }
        let grant = try await fixture.store.authorization(forLibraryID: fixture.library.id)

        await #expect(throws: PlexDownloadCreationAuthorizationError.mismatchedTransfer) {
            _ = try await fixture.store.schedule(
                fixture.transferRequest(accountID: 99),
                authorization: grant
            )
        }
        await #expect(throws: PlexDownloadCreationAuthorizationError.mismatchedTransfer) {
            _ = try await fixture.store.schedule(
                fixture.transferRequest(serverIdentifier: "different-server"),
                authorization: grant
            )
        }
        await #expect(throws: PlexDownloadCreationAuthorizationError.mismatchedTransfer) {
            _ = try await fixture.store.schedule(
                fixture.transferRequest(serverURL: "https://outside.example:32400"),
                authorization: grant
            )
        }
        await #expect(throws: PlexDownloadCreationAuthorizationError.mismatchedTransfer) {
            _ = try await fixture.store.schedule(
                fixture.transferRequest(librarySectionID: "2"),
                authorization: grant
            )
        }
        #expect(fixture.transferHarness.createdTaskCount == 0)
    }
}

@MainActor
private final class DownloadCreationFixture {
    let transferID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let rootURL: URL
    let defaults: UserDefaults
    let settings: PlexSettingsStore
    let connectionStore: PlexConnectionStore
    let libraryStore: PlexLibraryStore
    let browserStore: PlexBrowserStore
    let authStore: PlexAuthStore
    let transferHarness = DownloadCreationTransferHarness()
    let store: PlexDownloadCreationStore

    private let serverAllowsSync: Bool
    private let providerSupportsDownloads: Bool

    init(
        userHasPlexPass: Bool = true,
        serverAllowsSync: Bool = true,
        libraryAllowsSync: Bool = true,
        providerSupportsDownloads: Bool = true
    ) throws {
        self.serverAllowsSync = serverAllowsSync
        self.providerSupportsDownloads = providerSupportsDownloads
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PlexBarDownloadCreationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let suiteName = "PlexBarTests.DownloadCreation.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let credentials = PlexStoredCredentials(
            userToken: "user-token",
            serverToken: "server-token"
        )
        settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(credentials: credentials),
            initialCredentials: credentials
        )
        settings.selectedServerIdentifier = "server-id"
        settings.selectedServerName = "Server"
        connectionStore = PlexConnectionStore(settings: settings)
        connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "server-id",
            url: try #require(URL(string: "https://plex.local:32400")),
            kind: .local,
            validatedAt: Date()
        )

        let providerData = Self.providerData(
            serverAllowsSync: serverAllowsSync,
            providerSupportsDownloads: providerSupportsDownloads
        )
        let client = PlexAPIClient(session: Self.session(responseData: providerData))
        libraryStore = PlexLibraryStore(connectionStore: connectionStore, client: client)
        libraryStore.libraries = [Self.makeLibrary(allowSync: libraryAllowsSync)]
        browserStore = PlexBrowserStore(connectionStore: connectionStore, client: client)
        let sessionStore = PlexSessionStore(connectionStore: connectionStore, client: client)
        let historyStore = PlexHistoryStore(
            connectionStore: connectionStore,
            libraryStore: libraryStore,
            client: client,
            startsPolling: false
        )
        authStore = PlexAuthStore(
            settings: settings,
            connectionStore: connectionStore,
            sessionStore: sessionStore,
            historyStore: historyStore,
            libraryStore: libraryStore,
            deviceIdentityStore: PlexMemoryDeviceIdentityStore()
        )
        authStore.authenticatedUser = Self.makeUser(
            id: 42,
            hasPlexPass: userHasPlexPass
        )

        let handoffStore = PlexDownloadHandoffStore(rootURL: rootURL)
        let coordinator = PlexDownloadTransferCoordinator(
            registry: PlexDownloadTransferRegistry(rootURL: rootURL),
            packageStore: PlexDownloadPackageStore(rootURL: rootURL),
            handoffStore: handoffStore,
            session: transferHarness.session
        )
        store = PlexDownloadCreationStore(
            authStore: authStore,
            connectionStore: connectionStore,
            libraryStore: libraryStore,
            browserStore: browserStore,
            transferCoordinator: coordinator
        )
    }

    var library: PlexLibrary {
        Self.makeLibrary(allowSync: true)
    }

    func library(allowSync: Bool) -> PlexLibrary {
        Self.makeLibrary(allowSync: allowSync)
    }

    func user(id: Int) -> PlexAuthenticatedUser {
        Self.makeUser(id: id, hasPlexPass: true)
    }

    func restoreCredentials() {
        settings.userToken = "user-token"
        settings.serverToken = "server-token"
    }

    func restoreServer() {
        settings.selectedServerIdentifier = "server-id"
        connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "server-id",
            url: URL(string: "https://plex.local:32400")!,
            kind: .local,
            validatedAt: Date()
        )
    }

    func transferRequest(
        accountID: Int = 42,
        serverIdentifier: String = "server-id",
        serverURL: String = "https://plex.local:32400",
        librarySectionID: String = "1"
    ) -> PlexDownloadTransferRequest {
        let identity = PlexDownloadPackageIdentity(
            packageID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            accountID: accountID,
            serverIdentifier: serverIdentifier,
            queueID: 7,
            queueItemID: 11,
            metadataKey: "/library/metadata/42",
            ratingKey: "42"
        )
        var request = URLRequest(
            url: URL(string: "\(serverURL)/downloadQueue/7/item/11/media")!
        )
        request.httpMethod = "GET"
        request.setValue("server-token", forHTTPHeaderField: "X-Plex-Token")
        return PlexDownloadTransferRequest(
            packageIdentity: identity,
            title: "Movie",
            mediaType: "movie",
            decisionData: Data(#"{"MediaContainer":{"allowSync":"1","Metadata":[{"ratingKey":"42","key":"/library/metadata/42","librarySectionID":"\#(librarySectionID)","title":"Movie","type":"movie","Media":[]}]}}"#.utf8),
            mediaFileExtension: "mp4",
            contentType: "video/mp4",
            request: request
        )
    }

    func removeRoot() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func makeUser(
        id: Int,
        hasPlexPass: Bool
    ) -> PlexAuthenticatedUser {
        PlexAuthenticatedUser(
            id: id,
            username: "test-user",
            title: nil,
            email: nil,
            thumb: nil,
            friendlyName: nil,
            subscriptions: hasPlexPass ? [PlexUserSubscription(
                type: "plexpass",
                state: "active",
                mode: "recurring",
                active: true,
                subscribedAt: nil
            )] : []
        )
    }

    private static func makeLibrary(allowSync: Bool) -> PlexLibrary {
        PlexLibrary(
            id: "1",
            title: "Movies",
            type: .movie,
            compositePath: nil,
            artPath: nil,
            thumbPath: nil,
            itemCount: 1,
            secondaryCount: nil,
            secondaryCountLabel: nil,
            updatedAt: nil,
            scannedAt: nil,
            contentChangedAt: nil,
            latestAddedAt: nil,
            latestItemTitle: nil,
            allowSync: allowSync
        )
    }

    private static func providerData(
        serverAllowsSync: Bool,
        providerSupportsDownloads: Bool
    ) -> Data {
        let features = providerSupportsDownloads
            ? #"[{"type":"subscribe","flavor":"download"}]"#
            : "[]"
        return Data(#"{"MediaContainer":{"allowSync":\#(serverAllowsSync),"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":\#(features)}]}}"#.utf8)
    }

    private static func session(responseData: Data) -> URLSession {
        DownloadCreationURLProtocol.responseData = responseData
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadCreationURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class DownloadCreationTransferHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var createdCount = 0
    private var resumed: [Int] = []
    private let stream = AsyncStream.makeStream(of: PlexDownloadTransferEvent.self)

    var createdTaskCount: Int {
        lock.withLock { createdCount }
    }

    var resumedTaskIdentifiers: [Int] {
        lock.withLock { resumed }
    }

    var session: PlexDownloadTransferSession {
        PlexDownloadTransferSession(
            events: stream.stream,
            createTask: { [weak self] _, _ in
                self?.lock.withLock {
                    self?.createdCount += 1
                }
                return 41
            },
            tasks: { [] },
            resumeTask: { [weak self] identifier in
                self?.lock.withLock {
                    self?.resumed.append(identifier)
                }
            },
            cancelTask: { _ in }
        )
    }
}

private final class DownloadCreationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
