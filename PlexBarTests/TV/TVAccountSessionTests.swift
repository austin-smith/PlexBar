#if os(tvOS)
import Foundation
import PlexClientKit
import PlexModels
import PlexTopShelf
import Synchronization
import Testing
@testable import PlexBarTV

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct TVAccountSessionTests {
    @Test(arguments: ["choose", "reconnect", "device-authorization"], [200, 401, 500])
    func lateDiscoveryCannotRestoreServersAfterSignOut(operation: String, status: Int) async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let gate = TVAccountResponseGate()
        await fixture.server.holdDiscovery(gate, status: status)
        let old = Task { await fixture.discover(operation) }
        await gate.waitUntilEntered()
        await fixture.server.rejectNewAuthorizations()
        await fixture.store.logout()
        try await waitUntil { !fixture.store.isPairing }
        let signOutError = fixture.store.errorMessage
        await gate.release()
        await old.value
        #expect(!fixture.store.hasAuthorizedAccount)
        #expect(fixture.store.availableServers.isEmpty)
        #expect(fixture.store.connection == nil)
        #expect(fixture.store.errorMessage == signOutError)
        await fixture.store.selectServer(fixture.oldServer)
        #expect(fixture.store.connection == nil)
        #expect(await fixture.server.identityRequests == 0)
        #expect(await fixture.server.refreshRequests == 0)
    }

    @Test(arguments: ["choose", "reconnect"], [200, 401, 500])
    func lateDiscoveryCannotReplaceANewerAccount(operation: String, status: Int) async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let gate = TVAccountResponseGate()
        await fixture.server.holdDiscovery(gate, status: status)
        let old = Task { await fixture.discover(operation) }
        await gate.waitUntilEntered()
        await fixture.server.rejectNewAuthorizations()
        await fixture.store.logout()
        try await waitUntil { !fixture.store.isPairing }
        try await fixture.storage.persistAccountToken(Fixture.token("new"))
        await fixture.store.reconnectAuthorizedAccount()
        let current = try #require(fixture.store.availableServers.first(where: { $0.id == "server-id" }))
        #expect(current.accessToken == "server-token-new")
        await fixture.store.selectServer(current)
        #expect(fixture.store.connection?.token == "server-token-new")
        await gate.release()
        await old.value
        #expect(fixture.store.hasAuthorizedAccount)
        #expect(fixture.store.availableServers.isEmpty)
        #expect(fixture.store.connection?.token == "server-token-new")
        #expect(fixture.store.errorMessage == nil)
        await fixture.store.selectServer(fixture.oldServer)
        #expect(fixture.store.connection?.token == "server-token-new")
        #expect(await fixture.server.identityRequests == 1)
        #expect(await fixture.server.refreshRequests == 0)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }

    @MainActor
    private final class Fixture {
        let suite = "TVAccountSessionTests.\(UUID())"
        let defaults: UserDefaults
        let server: TVAccountServer
        let session: URLSession
        let storage: TVPlexAccountJWTStorage
        let store: TVAppStore
        let cache: TVTopShelfCache
        let publisher: TVTopShelfPublisher
        let oldServer = PlexServerResource(id: "server-id", name: "Server", productVersion: nil, accessToken: "server-token-old", connections: [
            PlexServerConnection(uri: URL(string: "https://plex.test")!, local: true, relay: false)
        ])

        init() async throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            let token = try Self.token("old")
            server = TVAccountServer(token: token)
            let server = server
            TVAccountSessionProtocol.handler.withLock { $0 = { try await server.respond($0) } }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [TVAccountSessionProtocol.self]
            session = URLSession(configuration: config)
            storage = TVPlexAccountJWTStorage(defaults: defaults, credentialStore: PlexMemoryCredentialStore(
                credentials: PlexStoredCredentials(userToken: token, serverToken: "")
            ))
            try await storage.loadAccountToken()
            cache = TVTopShelfCache(directory: URL.temporaryDirectory.appending(path: suite))
            let cache = cache
            publisher = TVTopShelfPublisher(cache: { cache }, notify: {})
            store = TVAppStore(
                client: TVPlexClient(session: session), defaults: defaults, authClient: PlexAuthClient(session: session),
                deviceIdentityStore: PlexMemoryDeviceIdentityStore(), keychain: KeychainStore(service: suite),
                topShelfPublisher: publisher, accountStorage: storage
            )
        }

        static func token(_ signature: String) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: ["exp": Int(Date().addingTimeInterval(7 * 86_400).timeIntervalSince1970)])
            let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            return "eyJhbGciOiJFZERTQSJ9.\(payload).\(signature)"
        }

        func discover(_ operation: String) async {
            switch operation {
            case "choose": await store.chooseServer()
            case "reconnect": await store.reconnectAuthorizedAccount()
            default: store.startPlexDeviceAuthorization()
            }
        }

        func close() {
            session.invalidateAndCancel()
            publisher.clear()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}

private actor TVAccountResponseGate {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    func block() async { await withCheckedContinuation { pending = $0; entered = true; entry?.resume(); entry = nil } }
    func waitUntilEntered() async { if !entered { await withCheckedContinuation { entry = $0 } } }
    func release() { pending?.resume(); pending = nil }
}

private actor TVAccountServer {
    private let token: String
    private var acceptsAuthorizations = true
    private var discovery: (TVAccountResponseGate, Int)?
    private(set) var identityRequests = 0
    private(set) var refreshRequests = 0
    init(token: String) { self.token = token }
    func holdDiscovery(_ gate: TVAccountResponseGate, status: Int) { discovery = (gate, status) }
    func rejectNewAuthorizations() { acceptsAuthorizations = false }
    func respond(_ request: URLRequest) async throws -> (Int, Data) {
        let path = request.url!.path
        let account = request.value(forHTTPHeaderField: "X-Plex-Token")?.hasSuffix(".new") == true ? "new" : "old"
        var status = 200
        if path == "/api/v2/resources", let (gate, code) = discovery {
            discovery = nil
            status = code
            await gate.block()
        }
        let json: String
        switch path {
        case "/api/v2/pins":
            if !acceptsAuthorizations { return (500, Data()) }
            json = #"{"id":1,"code":"testcode"}"#
        case "/api/v2/pins/1": json = #"{"id":1,"code":"testcode","authToken":"\#(token)"}"#
        case "/api/v2/resources": json = #"[{"name":"Server","clientIdentifier":"server-id","provides":"server","connections":[{"uri":"https://plex.test","local":true,"relay":false}]},{"name":"Second","clientIdentifier":"second","provides":"server","connections":[{"uri":"https://second.test","local":true,"relay":false}]}]"#
        case "/api/v2/devices": json = #"[{"name":"Server","clientIdentifier":"server-id","provides":"server","token":"server-token-\#(account)","connections":[{"uri":"https://plex.test"}]},{"name":"Second","clientIdentifier":"second","provides":"server","token":"second-token","connections":[{"uri":"https://second.test"}]}]"#
        case "/identity": identityRequests += 1; json = #"{"MediaContainer":{"machineIdentifier":"server-id","friendlyName":"Server"}}"#
        case "/media/providers": json = #"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"promoted","key":"/hubs/promoted"},{"type":"continuewatching","key":"/hubs/continueWatching"}]}]}}"#
        case "/hubs/promoted", "/hubs/continueWatching": json = #"{"MediaContainer":{"Hub":[]}}"#
        case "/library/sections/all": json = #"{"MediaContainer":{"Directory":[]}}"#
        case "/api/v2/auth/nonce", "/api/v2/auth/token": refreshRequests += 1; throw URLError(.unsupportedURL)
        default: throw URLError(.unsupportedURL)
        }
        return (status, Data(json.utf8))
    }
}

private final class TVAccountSessionProtocol: URLProtocol, @unchecked Sendable {
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
#endif
