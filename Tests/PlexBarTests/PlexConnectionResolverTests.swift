import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexConnectionResolverTests {
    @Test func prefersReachableLocalConnection() async throws {
        let session = makeResolverSession { request in
            let url = try #require(request.url)

            if url.path == "/identity", url.host == "plex.local" {
                return try identityResponse(url: url, serverID: "server-id")
            }

            Issue.record("Unexpected request: \(request)")
            throw URLError(.unsupportedURL)
        }

        let resolver = PlexConnectionResolver(
            client: PlexAPIClient(session: session),
            probeTimeoutInterval: 0.1
        )

        let resolved = try await resolver.resolve(
            server: makeServer(
                id: "server-id",
                connections: [
                    .init(uri: URL(string: "https://plex.local:32400")!, local: true, relay: false),
                    .init(uri: URL(string: "https://plex.remote:32400")!, local: false, relay: false),
                    .init(uri: URL(string: "https://plex.relay:8443")!, local: false, relay: true),
                ]
            ),
            clientContext: PlexClientContext(clientIdentifier: "client-123"),
            cachedURL: nil
        )

        #expect(resolved.kind == .local)
        #expect(resolved.url.host == "plex.local")
    }

    @Test func prefersHTTPSWithinSameTierEvenIfHTTPRespondsFaster() async throws {
        let session = makeResolverSession { request in
            let url = try #require(request.url)

            if url.path == "/identity", url.scheme == "https", url.host == "plex.local" {
                Thread.sleep(forTimeInterval: 0.05)
                return try identityResponse(url: url, serverID: "server-id")
            }

            if url.path == "/identity", url.scheme == "http", url.host == "plex.local" {
                return try identityResponse(url: url, serverID: "server-id")
            }

            Issue.record("Unexpected request: \(request)")
            throw URLError(.unsupportedURL)
        }

        let resolver = PlexConnectionResolver(
            client: PlexAPIClient(session: session),
            probeTimeoutInterval: 0.1
        )

        let resolved = try await resolver.resolve(
            server: makeServer(
                id: "server-id",
                connections: [
                    .init(uri: URL(string: "http://plex.local:32400")!, local: true, relay: false),
                    .init(uri: URL(string: "https://plex.local:32400")!, local: true, relay: false),
                ]
            ),
            clientContext: PlexClientContext(clientIdentifier: "client-123"),
            cachedURL: nil
        )

        #expect(resolved.url.scheme == "https")
    }

    @Test func fallsBackToRemoteWhenLocalProbeFails() async throws {
        let session = makeResolverSession { request in
            let url = try #require(request.url)

            if url.path == "/identity", url.host == "plex.local" {
                throw URLError(.cannotConnectToHost)
            }

            if url.path == "/identity", url.host == "plex.remote" {
                return try identityResponse(url: url, serverID: "server-id")
            }

            Issue.record("Unexpected request: \(request)")
            throw URLError(.unsupportedURL)
        }

        let resolver = PlexConnectionResolver(
            client: PlexAPIClient(session: session),
            probeTimeoutInterval: 0.1
        )

        let resolved = try await resolver.resolve(
            server: makeServer(
                id: "server-id",
                connections: [
                    .init(uri: URL(string: "https://plex.local:32400")!, local: true, relay: false),
                    .init(uri: URL(string: "https://plex.remote:32400")!, local: false, relay: false),
                ]
            ),
            clientContext: PlexClientContext(clientIdentifier: "client-123"),
            cachedURL: nil
        )

        #expect(resolved.kind == .remote)
        #expect(resolved.url.host == "plex.remote")
    }

    @Test func fallsBackToRelayWhenDirectConnectionsFail() async throws {
        let session = makeResolverSession { request in
            let url = try #require(request.url)

            if url.path == "/identity", url.host == "plex.local" {
                throw URLError(.cannotConnectToHost)
            }

            if url.path == "/identity", url.host == "plex.remote" {
                throw URLError(.timedOut)
            }

            if url.path == "/identity", url.host == "plex.relay" {
                return try identityResponse(url: url, serverID: "server-id")
            }

            Issue.record("Unexpected request: \(request)")
            throw URLError(.unsupportedURL)
        }

        let resolver = PlexConnectionResolver(
            client: PlexAPIClient(session: session),
            probeTimeoutInterval: 0.1
        )

        let resolved = try await resolver.resolve(
            server: makeServer(
                id: "server-id",
                connections: [
                    .init(uri: URL(string: "https://plex.local:32400")!, local: true, relay: false),
                    .init(uri: URL(string: "https://plex.remote:32400")!, local: false, relay: false),
                    .init(uri: URL(string: "https://plex.relay:8443")!, local: false, relay: true),
                ]
            ),
            clientContext: PlexClientContext(clientIdentifier: "client-123"),
            cachedURL: nil
        )

        #expect(resolved.kind == .relay)
        #expect(resolved.url.host == "plex.relay")
    }

    @Test func cachedValidConnectionIsReusedBeforeFreshResolution() async throws {
        let counter = RequestCounter()
        let session = makeResolverSession { request in
            let url = try #require(request.url)

            if url.path == "/identity", url.host == "plex.remote" {
                let attempts = counter.incrementAndReturn(for: "identity.remote")
                #expect(attempts == 1)
                return try identityResponse(url: url, serverID: "server-id")
            }

            Issue.record("Unexpected request: \(request)")
            throw URLError(.unsupportedURL)
        }

        let resolver = PlexConnectionResolver(
            client: PlexAPIClient(session: session),
            probeTimeoutInterval: 0.1
        )
        let cachedURL = try #require(URL(string: "https://plex.remote:32400"))
        let resolved = try await resolver.resolve(
            server: makeServer(
                id: "server-id",
                connections: [
                    .init(uri: URL(string: "https://plex.local:32400")!, local: true, relay: false),
                    .init(uri: cachedURL, local: false, relay: false),
                ]
            ),
            clientContext: PlexClientContext(clientIdentifier: "client-123"),
            cachedURL: cachedURL
        )

        #expect(resolved.url == cachedURL)
    }

    @Test func cachedUnreachableConnectionTriggersFreshResolution() async throws {
        let session = makeResolverSession { request in
            let url = try #require(request.url)

            if url.path == "/identity", url.host == "plex.remote" {
                throw URLError(.cannotConnectToHost)
            }

            if url.path == "/identity", url.host == "plex.fallback" {
                return try identityResponse(url: url, serverID: "server-id")
            }

            Issue.record("Unexpected request: \(request)")
            throw URLError(.unsupportedURL)
        }

        let resolver = PlexConnectionResolver(
            client: PlexAPIClient(session: session),
            probeTimeoutInterval: 0.1
        )
        let cachedURL = try #require(URL(string: "https://plex.remote:32400"))
        let resolved = try await resolver.resolve(
            server: makeServer(
                id: "server-id",
                connections: [
                    .init(uri: URL(string: "https://plex.fallback:32400")!, local: false, relay: false),
                    .init(uri: cachedURL, local: false, relay: false),
                ]
            ),
            clientContext: PlexClientContext(clientIdentifier: "client-123"),
            cachedURL: cachedURL
        )

        #expect(resolved.url.host == "plex.fallback")
    }

    @Test func hardFailingProbeDoesNotSilentlyFailOver() async throws {
        let session = makeResolverSession { request in
            let url = try #require(request.url)

            if url.path == "/identity", url.host == "plex.local" {
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                ))
                let data = Data("{}".utf8)
                return (response, data)
            }

            if url.path == "/identity", url.host == "plex.remote" {
                return try identityResponse(url: url, serverID: "server-id")
            }

            Issue.record("Unexpected request: \(request)")
            throw URLError(.unsupportedURL)
        }

        let resolver = PlexConnectionResolver(
            client: PlexAPIClient(session: session),
            probeTimeoutInterval: 0.1
        )

        do {
            _ = try await resolver.resolve(
                server: makeServer(
                    id: "server-id",
                    connections: [
                        .init(uri: URL(string: "https://plex.local:32400")!, local: true, relay: false),
                        .init(uri: URL(string: "https://plex.remote:32400")!, local: false, relay: false),
                    ]
                ),
                clientContext: PlexClientContext(clientIdentifier: "client-123"),
                cachedURL: nil
            )
            Issue.record("Expected hard failure to stop resolution")
        } catch let error as PlexAPIError {
            guard case .badStatusCode(let statusCode) = error else {
                Issue.record("Unexpected PlexAPIError: \(error)")
                return
            }

            #expect(statusCode == 401)
        }
    }

    @Test func identityMismatchDoesNotSilentlyFailOver() async throws {
        let session = makeResolverSession { request in
            let url = try #require(request.url)

            if url.path == "/identity", url.host == "plex.local" {
                return try identityResponse(url: url, serverID: "wrong-server")
            }

            if url.path == "/identity", url.host == "plex.remote" {
                return try identityResponse(url: url, serverID: "server-id")
            }

            Issue.record("Unexpected request: \(request)")
            throw URLError(.unsupportedURL)
        }

        let resolver = PlexConnectionResolver(
            client: PlexAPIClient(session: session),
            probeTimeoutInterval: 0.1
        )

        do {
            _ = try await resolver.resolve(
                server: makeServer(
                    id: "server-id",
                    connections: [
                        .init(uri: URL(string: "https://plex.local:32400")!, local: true, relay: false),
                        .init(uri: URL(string: "https://plex.remote:32400")!, local: false, relay: false),
                    ]
                ),
                clientContext: PlexClientContext(clientIdentifier: "client-123"),
                cachedURL: nil
            )
            Issue.record("Expected identity mismatch to stop resolution")
        } catch let error as PlexConnectionResolutionError {
            guard case .identityMismatch(let expected, let actual, let url) = error else {
                Issue.record("Unexpected resolver error: \(error)")
                return
            }

            #expect(expected == "server-id")
            #expect(actual == "wrong-server")
            #expect(url.host == "plex.local")
        }
    }

    @MainActor
    @Test func connectionStoreRetriesWithFreshResolutionAfterConnectivityFailure() async throws {
        let suiteName = "PlexBarTests.connectionStoreRetriesWithFreshResolutionAfterConnectivityFailure"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let counter = RequestCounter()
        let session = makeResolverSession { request in
            let url = try #require(request.url)

            if url.path == "/identity", url.host == "plex.local" {
                let identityAttempts = counter.incrementAndReturn(for: "identity.local")
                if identityAttempts == 1 {
                    return try identityResponse(url: url, serverID: "server-id")
                }

                throw URLError(.cannotConnectToHost)
            }

            if url.path == "/identity", url.host == "plex.remote" {
                return try identityResponse(url: url, serverID: "server-id")
            }

            if url.path == "/status/sessions", url.host == "plex.local" {
                throw URLError(.timedOut)
            }

            if url.path == "/status/sessions", url.host == "plex.remote" {
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                let data = try #require(#"{"MediaContainer":{"Metadata":[]}}"#.data(using: .utf8))
                return (response, data)
            }

            Issue.record("Unexpected request: \(request)")
            throw URLError(.unsupportedURL)
        }

        let settings = PlexSettingsStore(
            defaults: defaults,
            keychain: KeychainStore(service: "tests.\(suiteName)")
        )
        let server = makeServer(
            id: "server-id",
            connections: [
                .init(uri: URL(string: "https://plex.local:32400")!, local: true, relay: false),
                .init(uri: URL(string: "https://plex.remote:32400")!, local: false, relay: false),
            ]
        )
        settings.saveServerSelection(server)

        let resolver = PlexConnectionResolver(
            client: PlexAPIClient(session: session),
            probeTimeoutInterval: 0.1
        )
        let connectionStore = PlexConnectionStore(
            settings: settings,
            resolver: resolver
        )
        connectionStore.updateAvailableServers([server])

        let client = PlexAPIClient(session: session)
        let sessions = try await connectionStore.perform { configuration in
            try await client.fetchSessions(using: configuration)
        }

        #expect(sessions.isEmpty)
        #expect(connectionStore.activeConnectionKind == .remote)
        #expect(connectionStore.resolvedServerURL?.host == "plex.remote")
        #expect(settings.normalizedServerURL?.host == "plex.remote")
    }

    @MainActor
    @Test func connectionStorePublishesResolutionErrorsAndClearsThemAfterRecovery() async throws {
        let suiteName = "PlexBarTests.connectionStorePublishesResolutionErrorsAndClearsThemAfterRecovery"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let counter = RequestCounter()
        let session = makeResolverSession { request in
            let url = try #require(request.url)

            if url.path == "/identity", url.host == "plex.local" {
                let attempts = counter.incrementAndReturn(for: "identity.local")
                if attempts == 1 {
                    throw URLError(.cannotConnectToHost)
                }

                return try identityResponse(url: url, serverID: "server-id")
            }

            Issue.record("Unexpected request: \(request)")
            throw URLError(.unsupportedURL)
        }

        let settings = PlexSettingsStore(
            defaults: defaults,
            keychain: KeychainStore(service: "tests.\(suiteName)")
        )
        let server = makeServer(
            id: "server-id",
            connections: [
                .init(uri: URL(string: "https://plex.local:32400")!, local: true, relay: false),
            ]
        )
        settings.saveServerSelection(server)

        let connectionStore = PlexConnectionStore(
            settings: settings,
            resolver: PlexConnectionResolver(
                client: PlexAPIClient(session: session),
                probeTimeoutInterval: 0.1
            )
        )
        connectionStore.updateAvailableServers([server])

        await #expect(throws: PlexConnectionResolutionError.self) {
            try await connectionStore.currentConfiguration()
        }
        #expect(connectionStore.errorMessage != nil)
        #expect(connectionStore.activeConnection == nil)

        let configuration = try await connectionStore.currentConfiguration(forceRefresh: true)
        #expect(configuration.serverURL.host == "plex.local")
        #expect(connectionStore.errorMessage == nil)
        #expect(connectionStore.resolvedServerURL?.host == "plex.local")
        #expect(connectionStore.activeConnection?.url.host == "plex.local")
    }
}

private func makeServer(
    id: String,
    connections: [PlexServerConnection]
) -> PlexServerResource {
    PlexServerResource(
        id: id,
        name: "Server",
        productVersion: "1.0.0",
        accessToken: "server-token",
        connections: connections
    )
}

private func identityResponse(url: URL, serverID: String) throws -> (HTTPURLResponse, Data) {
    let response = try #require(HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let data = try #require(#"""
    {
      "MediaContainer": {
        "claimed": true,
        "machineIdentifier": "\#(serverID)",
        "version": "1.0.0"
      }
    }
    """#.data(using: .utf8))
    return (response, data)
}

private func makeResolverSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    ResolverMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResolverMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class ResolverMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func incrementAndReturn(for key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        counts[key, default: 0] += 1
        return counts[key, default: 0]
    }
}
