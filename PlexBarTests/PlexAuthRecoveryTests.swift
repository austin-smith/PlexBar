import Foundation
import Testing
@testable import PlexBar

@MainActor
struct PlexAuthRecoveryTests {
    @Test func rejectedUnexpiredJWTIsRefreshedBeforeServerDiscoveryRetries() async throws {
        let now = Date()
        let rejectedToken = try accountJWT(
            expiration: now.addingTimeInterval(3 * 24 * 60 * 60),
            signature: "rejected"
        )
        let refreshedToken = try accountJWT(
            expiration: now.addingTimeInterval(7 * 24 * 60 * 60),
            signature: "refreshed"
        )
        let requestCounter = AuthRecoveryRequestCounter()
        let session = makeAuthRecoverySession { request in
            let url = try #require(request.url)

            switch url.path {
            case "/api/v2/resources":
                let attempt = requestCounter.incrementAndReturn()
                let token = request.value(forHTTPHeaderField: "X-Plex-Token")
                if attempt == 1 {
                    #expect(token == rejectedToken)
                    return try authRecoveryResponse(url: url, statusCode: 401, data: Data())
                }

                #expect(token == refreshedToken)
                let data = try #require(#"""
                [
                  {
                    "name": "Test Server",
                    "clientIdentifier": "server-id",
                    "provides": "server",
                    "accessToken": "server-token",
                    "connections": [
                      { "uri": "https://plex.test:32400", "local": false, "relay": false }
                    ]
                  }
                ]
                """#.data(using: .utf8))
                return try authRecoveryResponse(url: url, statusCode: 200, data: data)

            case "/api/v2/devices":
                #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == refreshedToken)
                let data = try #require(#"""
                [
                  {
                    "name": "Test Server",
                    "clientIdentifier": "server-id",
                    "provides": "server",
                    "token": "server-token",
                    "connections": [
                      { "uri": "https://plex.test:32400" }
                    ]
                  }
                ]
                """#.data(using: .utf8))
                return try authRecoveryResponse(url: url, statusCode: 200, data: data)

            case "/api/v2/auth/nonce":
                let data = try #require(#"{"nonce":"test-nonce"}"#.data(using: .utf8))
                return try authRecoveryResponse(url: url, statusCode: 200, data: data)

            case "/api/v2/auth/token":
                let data = try JSONEncoder().encode(["auth_token": refreshedToken])
                return try authRecoveryResponse(url: url, statusCode: 200, data: data)

            default:
                Issue.record("Unexpected request: \(request)")
                throw URLError(.unsupportedURL)
            }
        }

        let suiteName = "PlexBarTests.PlexAuthRecovery.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = PlexStoredCredentials(userToken: rejectedToken, serverToken: "server-token")
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(credentials: credentials),
            initialCredentials: credentials
        )
        let connectionStore = PlexConnectionStore(settings: settings)
        let apiClient = PlexAPIClient(session: session)
        let libraryStore = PlexLibraryStore(connectionStore: connectionStore, client: apiClient)
        let sessionStore = PlexSessionStore(connectionStore: connectionStore, client: apiClient)
        let historyStore = PlexHistoryStore(
            connectionStore: connectionStore,
            libraryStore: libraryStore,
            client: apiClient
        )
        let selectedServer = PlexServerResource(
            id: "server-id",
            name: "Test Server",
            productVersion: nil,
            accessToken: "server-token",
            connections: [
                PlexServerConnection(
                    uri: URL(string: "https://plex.test:32400")!,
                    local: false,
                    relay: false
                )
            ]
        )
        settings.saveServerSelection(selectedServer)
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "device-key")
        let authClient = PlexAuthClient(session: session)
        let tokenManager = PlexAccountJWTManager(
            settings: settings,
            client: authClient,
            deviceIdentityStore: PlexMemoryDeviceIdentityStore(identity: identity)
        )
        let authStore = PlexAuthStore(
            settings: settings,
            connectionStore: connectionStore,
            sessionStore: sessionStore,
            historyStore: historyStore,
            libraryStore: libraryStore,
            client: authClient,
            deviceIdentityStore: PlexMemoryDeviceIdentityStore(identity: identity),
            accountJWTManager: tokenManager
        )

        await authStore.refreshServers()

        #expect(authStore.errorMessage == nil)
        #expect(authStore.availableServers.map(\.id) == ["server-id"])
        #expect(settings.userToken == refreshedToken)
        #expect(requestCounter.value == 2)
    }

    private func accountJWT(expiration: Date, signature: String) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "EdDSA"])
        let payload = try JSONSerialization.data(withJSONObject: [
            "exp": Int(expiration.timeIntervalSince1970)
        ])
        return "\(base64URL(header)).\(base64URL(payload)).\(signature)"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private func makeAuthRecoverySession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    AuthRecoveryURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthRecoveryURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func authRecoveryResponse(
    url: URL,
    statusCode: Int,
    data: Data
) throws -> (HTTPURLResponse, Data) {
    let response = try #require(HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    ))
    return (response, data)
}

private final class AuthRecoveryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

private final class AuthRecoveryRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func incrementAndReturn() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
