import AppKit
import Foundation
import PlexClientKit
import PlexModels
import SwiftUI
import Synchronization
import Testing
@testable import PlexBar

@MainActor
@Suite(.serialized)
struct PlexServerSwitchTests {
    @Test(arguments: [PlexTimelineState.playing, .stopped])
    func timelineRequiresTheOriginalPlaybackScope(state: PlexTimelineState) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let originalScope = fixture.connection.accountCacheScope
        fixture.selectServer("second")

        let rejected = await fixture.browser.reportTimeline(update(state), accountScope: originalScope)
        #expect(rejected == nil)
        #expect(await fixture.server.requests.isEmpty)

        let accepted = await fixture.browser.reportTimeline(
            update(state), accountScope: fixture.connection.accountCacheScope
        )
        #expect(accepted != nil)
        let timelines = await fixture.server.requests.filter { $0.url?.path == "/timeline" }
        #expect(timelines.count == 1)
        #expect(timelines.first?.url?.host == "second.local")
    }

    @Test func queuedStopDoesNotMoveToTheNewServer() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let scope = fixture.connection.accountCacheScope
        let gate = ResponseGate()
        await fixture.server.hold(host: "first.local", path: "/timeline", at: gate)
        let reporter = PlexTimelineReportSequencer { [browser = fixture.browser] update in
            await browser.reportTimeline(update, accountScope: scope)
        }

        let playing = Task { await reporter.report(update(.playing)) }
        try await waitUntil { await gate.entered }
        let stopped = Task { await reporter.report(update(.stopped)) }
        fixture.selectServer("second")
        await gate.release()
        _ = await (playing.value, stopped.value)

        let timelines = await fixture.server.requests.filter { $0.url?.path == "/timeline" }
        #expect(timelines.count == 1)
        #expect(timelines.first?.url?.host == "first.local")
        #expect(timelines.first?.url?.query?.contains("state=playing") == true)
    }

    @Test func homeReloadsAfterResetWithoutRecreatingItsView() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let hostingView = NSHostingView(rootView: PlexHomeView(
            browserStore: fixture.browser,
            settingsStore: fixture.settings,
            connectionStore: fixture.connection,
            playerCoordinator: PlexPlayerCoordinator()
        ).environment(fixture.makeDownloadsStore()))
        let window = NSWindow(
            contentRect: CGRect(x: -10_000, y: -10_000, width: 800, height: 600),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.close() }

        try await waitUntil { fixture.browser.hasLoadedHomeHubs }
        #expect(fixture.browser.homeHubs.first?.title == "first.local")
        #expect(fixture.browser.supportsPlaylistCreation)

        fixture.selectServer("second")
        // The same mounted Home view must observe the reset and start a new load.
        try await waitUntil { fixture.browser.hasLoadedHomeHubs }
        #expect(fixture.browser.homeHubs.first?.title == "second.local")
        #expect(fixture.browser.supportsPlaylistCreation)
        #expect(window.contentView === hostingView)
    }

    @Test(arguments: [false, true])
    func previousHomeCompletionCannotChangeTheNewLoad(fails: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let oldGate = ResponseGate(fails: fails)
        let newGate = ResponseGate()
        await fixture.server.hold(host: "first.local", path: "/home", at: oldGate)
        await fixture.server.hold(host: "second.local", path: "/home", at: newGate)

        let oldLoad = Task { await fixture.browser.loadHomeHubs() }
        try await waitUntil { await oldGate.entered }
        fixture.selectServer("second")
        let newLoad = Task { await fixture.browser.loadHomeHubs() }
        try await waitUntil { await newGate.entered }

        await oldGate.release()
        await oldLoad.value
        #expect(fixture.browser.isLoadingHomeHubs)
        #expect(!fixture.browser.hasLoadedHomeHubs)
        #expect(fixture.browser.homeHubs.isEmpty)
        #expect(fixture.browser.homeHubsErrorMessage == nil)

        await newGate.release()
        await newLoad.value
        #expect(!fixture.browser.isLoadingHomeHubs)
        #expect(fixture.browser.homeHubs.first?.title == "second.local")
        #expect(fixture.browser.homeHubsErrorMessage == nil)
    }

    private func update(_ state: PlexTimelineState) -> PlexTimelineUpdate {
        PlexTimelineUpdate(
            ratingKey: "42", state: state, time: 30_000,
            duration: 120_000, sessionIdentifier: "original-playback"
        )
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(await condition(), "Timed out waiting for the test operation")
    }

    @MainActor
    private final class Fixture {
        let suite = "PlexServerSwitchTests.\(UUID().uuidString)"
        let settings: PlexSettingsStore
        let connection: PlexConnectionStore
        let browser: PlexBrowserStore
        let server = MockServer()
        let session: URLSession
        let defaults: UserDefaults

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            let credentials = PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
            settings = PlexSettingsStore(
                defaults: defaults,
                credentialStore: PlexMemoryCredentialStore(credentials: credentials),
                initialCredentials: credentials
            )
            connection = PlexConnectionStore(settings: settings)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ServerSwitchMockProtocol.self]
            session = URLSession(configuration: configuration)
            browser = PlexBrowserStore(connectionStore: connection, client: PlexAPIClient(session: session))
            let server = server
            ServerSwitchMockProtocol.handler.withLock { $0 = { try await server.respond(to: $0) } }
            selectServer("first")
        }

        func selectServer(_ name: String) {
            settings.selectedServerIdentifier = name
            connection.activeConnection = PlexResolvedConnection(
                serverID: name, url: URL(string: "https://\(name).local:32400")!,
                kind: .local, validatedAt: Date()
            )
            browser.resetServerScopedState()
        }

        func close() {
            session.invalidateAndCancel()
            ServerSwitchMockProtocol.handler.withLock { $0 = nil }
            defaults.removePersistentDomain(forName: suite)
        }

        func makeDownloadsStore() -> PlexDownloadsStore {
            let client = PlexAPIClient(session: session)
            let library = PlexLibraryStore(connectionStore: connection, client: client)
            let history = PlexHistoryStore(connectionStore: connection, libraryStore: library, client: client, startsPolling: false)
            let auth = PlexAuthStore(
                settings: settings, connectionStore: connection,
                sessionStore: PlexSessionStore(connectionStore: connection, client: client),
                historyStore: history, libraryStore: library
            )
            let root = URL.temporaryDirectory.appendingPathComponent(suite)
            let packages = PlexDownloadPackageStore(rootURL: root)
            let transfers = PlexDownloadTransferCoordinator.inert(rootURL: root, packageStore: packages)
            return PlexDownloadsStore(
                authStore: auth, connectionStore: connection, browserStore: browser, client: client,
                creationStore: PlexDownloadCreationStore(
                    authStore: auth, connectionStore: connection, libraryStore: library,
                    browserStore: browser, transferCoordinator: transfers
                ),
                transferCoordinator: transfers, packageStore: packages
            )
        }
    }
}

private actor ResponseGate {
    private(set) var entered = false
    private let fails: Bool
    private var continuation: CheckedContinuation<Void, Never>?

    init(fails: Bool = false) { self.fails = fails }

    func wait() async throws {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered = true
        }
        if fails { throw URLError(.badServerResponse) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor MockServer {
    private(set) var requests: [URLRequest] = []
    private var gates: [String: ResponseGate] = [:]

    func hold(host: String, path: String, at gate: ResponseGate) {
        gates[host + path] = gate
    }

    func respond(to request: URLRequest) async throws -> Data {
        requests.append(request)
        let url = try #require(request.url)
        if let gate = gates.removeValue(forKey: (url.host ?? "") + url.path) {
            try await gate.wait()
        }
        switch url.path {
        case "/media/providers":
            return Data(#"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"promoted","key":"/home"},{"type":"continuewatching","key":"/continue"},{"type":"timeline","key":"/timeline"},{"type":"playlist","key":"/playlists","readOnly":false}]}]}}"#.utf8)
        case "/home":
            return Data("""
            {"MediaContainer":{"Hub":[{"hubIdentifier":"recent","title":"\(url.host!)","Metadata":[{"ratingKey":"42","title":"Movie","type":"movie","Media":[]}]}]}}
            """.utf8)
        case "/continue":
            return Data(#"{"MediaContainer":{"Hub":[]}}"#.utf8)
        case "/timeline":
            return Data(#"{"MediaContainer":{}}"#.utf8)
        default:
            Issue.record("Unexpected mock request: \(url)")
            throw URLError(.badURL)
        }
    }
}

private final class ServerSwitchMockProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> Data
    static let handler = Mutex<Handler?>(nil)
    private let loadingTask = Mutex<Task<Void, Never>?>(nil)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler.withLock({ $0 }) else { return }
        let task = Task { @Sendable [self, request = request] in
            do {
                let data = try await handler(request)
                try Task.checkCancellation()
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                guard !Task.isCancelled else { return }
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        loadingTask.withLock { $0 = task }
    }

    override func stopLoading() { loadingTask.withLock { $0?.cancel() } }
}
