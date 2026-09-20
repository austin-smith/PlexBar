import PlexModels
#if os(tvOS)
import Foundation
import Synchronization
import Testing
@testable import PlexBarTV

@Suite(.serialized, .timeLimit(.minutes(1)))
struct TVConnectionResolutionTests {
    @Test func unreachableConnectionsPreserveTransportCauses() async throws {
        let fixture = Fixture(responses: [.failure(.timedOut), .failure(.timedOut)])
        defer { fixture.close() }
        do {
            _ = try await fixture.resolve()
            Issue.record("Expected connection timeout")
        } catch let failure as PlexServerConnectionFailure {
            #expect(failure.failureCodes == [.timedOut, .timedOut])
            #expect(failure.localizedDescription.contains(URLError(.timedOut).localizedDescription))
            #expect(failure.localizedDescription.components(separatedBy: URLError(.timedOut).localizedDescription).count == 2)
            #expect(!failure.localizedDescription.contains("test-token"))
        }
        #expect(TVConnectionMockProtocol.requests.withLock { $0.map { $0.url?.host } } == ["local.test", "remote.test"])
    }

    @Test(arguments: [401, 403])
    func authenticationFailuresStopResolution(status: Int) async throws {
        let fixture = Fixture(responses: [.response(status, "{}"), .identity("server")])
        defer { fixture.close() }
        do {
            _ = try await fixture.resolve()
            Issue.record("Expected authentication failure")
        } catch let failure as TVPlexError {
            guard case .badStatus(let receivedStatus) = failure else {
                Issue.record("Expected HTTP failure, received \(failure)")
                return
            }
            #expect(receivedStatus == status)
        }
        #expect(TVConnectionMockProtocol.requests.withLock { $0.count } == 1)
    }

    @Test func wrongServerIdentityStopsResolution() async throws {
        let fixture = Fixture(responses: [.identity("wrong-server"), .identity("server")])
        defer { fixture.close() }
        do {
            _ = try await fixture.resolve()
            Issue.record("Expected identity failure")
        } catch let failure as TVPlexError {
            guard case .serverIdentityMismatch(let expected, let actual) = failure else {
                Issue.record("Expected identity failure, received \(failure)")
                return
            }
            #expect(expected == "server")
            #expect(actual == "wrong-server")
        }
        #expect(TVConnectionMockProtocol.requests.withLock { $0.count } == 1)
    }

    @Test func reachableAdvertisedConnectionKeepsItsActualKind() async throws {
        let fixture = Fixture(responses: [.failure(.timedOut), .identity("server")])
        defer { fixture.close() }
        let resolved = try await fixture.resolve()
        #expect(resolved.connection.kind == .remote)
        #expect(resolved.connection.serverURL.host == "remote.test")
    }

    private struct Fixture {
        let client: TVPlexClient
        let session: URLSession

        init(responses: [TVConnectionMockProtocol.Response]) {
            TVConnectionMockProtocol.requests.withLock { $0 = [] }
            TVConnectionMockProtocol.responses.withLock { $0 = responses }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [TVConnectionMockProtocol.self]
            session = URLSession(configuration: configuration)
            client = TVPlexClient(session: session)
        }

        func resolve() async throws -> TVPlexResolvedServer {
            try await client.resolve(PlexServerResource(
                id: "server", name: "Test Plex", productVersion: nil, accessToken: "test-token",
                connections: [
                    .init(uri: URL(string: "https://remote.test")!, local: false, relay: false),
                    .init(uri: URL(string: "https://local.test")!, local: true, relay: false)
                ]
            ), clientIdentifier: "resolution-tests")
        }

        func close() { session.invalidateAndCancel() }
    }
}

private final class TVConnectionMockProtocol: URLProtocol, @unchecked Sendable {
    enum Response: Sendable {
        case failure(URLError.Code)
        case response(Int, String)

        static func identity(_ identifier: String) -> Self {
            .response(200, "{\"MediaContainer\":{\"machineIdentifier\":\"\(identifier)\"}}")
        }
    }
    static let requests = Mutex<[URLRequest]>([])
    static let responses = Mutex<[Response]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let next = Self.responses.withLock { $0.isEmpty ? Response.failure(.unsupportedURL) : $0.removeFirst() }
        switch next {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .response(let status, let body):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
#endif
