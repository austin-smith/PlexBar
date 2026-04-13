import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
@MainActor
struct PlexServerPreviewStoreTests {
    @Test func keepsExistingServerLoadAliveWhenAnotherServerStarts() async throws {
        let responder = PreviewStoreResponder()
        let session = makePreviewStoreSession(responder: responder)
        let store = PlexServerPreviewStore(client: PlexAPIClient(session: session))

        let firstServer = makeServer(id: "server-1", host: "plex.local")
        let secondServer = makeServer(id: "server-2", host: "plex-2.local")

        store.loadPreviewsIfNeeded(for: [firstServer], clientIdentifier: "client-123")
        store.loadPreviewsIfNeeded(for: [secondServer], clientIdentifier: "client-123")

        await waitForPreviewLoad(on: store, serverID: firstServer.id)
        await waitForPreviewLoad(on: store, serverID: secondServer.id)

        let firstState = store.state(for: firstServer.id)
        let secondState = store.state(for: secondServer.id)

        #expect(firstState.hasLoaded)
        #expect(firstState.isLoading == false)
        #expect(firstState.items.map(\.title) == ["First Server Movie"])
        #expect(secondState.hasLoaded)
        #expect(secondState.isLoading == false)
        #expect(secondState.items.map(\.title) == ["Second Server Movie"])
    }

    @Test func retriesServerPreviewAfterTransientFailure() async throws {
        let responder = PreviewStoreResponder()
        responder.failFirstPreviewRequest(forHost: "plex.local")

        let session = makePreviewStoreSession(responder: responder)
        let store = PlexServerPreviewStore(client: PlexAPIClient(session: session))
        let server = makeServer(id: "server-1", host: "plex.local")

        store.loadPreviewsIfNeeded(for: [server], clientIdentifier: "client-123")
        await waitForPreviewFailure(on: store, serverID: server.id)

        let failedState = store.state(for: server.id)
        #expect(failedState.hasLoaded == false)
        #expect(failedState.errorMessage != nil)

        store.loadPreviewsIfNeeded(for: [server], clientIdentifier: "client-123")
        await waitForPreviewLoad(on: store, serverID: server.id)

        let finalState = store.state(for: server.id)
        #expect(finalState.hasLoaded)
        #expect(finalState.errorMessage == nil)
        #expect(finalState.items.map(\.title) == ["First Server Movie"])
        #expect(responder.previewRequestCount(forHost: "plex.local") == 2)
    }

    @Test func refreshPreviewsReloadsAlreadyLoadedServers() async throws {
        let responder = PreviewStoreResponder()
        let session = makePreviewStoreSession(responder: responder)
        let store = PlexServerPreviewStore(client: PlexAPIClient(session: session))
        let server = makeServer(id: "server-1", host: "plex.local")

        store.loadPreviewsIfNeeded(for: [server], clientIdentifier: "client-123")
        await waitForPreviewLoad(on: store, serverID: server.id)

        #expect(responder.previewRequestCount(forHost: "plex.local") == 1)

        store.refreshPreviews(for: [server], clientIdentifier: "client-123")

        #expect(store.state(for: server.id).isLoading)

        await waitForPreviewLoad(on: store, serverID: server.id)

        #expect(store.state(for: server.id).hasLoaded)
        #expect(store.state(for: server.id).errorMessage == nil)
        #expect(responder.previewRequestCount(forHost: "plex.local") == 2)
    }

    private func makeServer(id: String, host: String) -> PlexServerResource {
        PlexServerResource(
            id: id,
            name: host,
            productVersion: "1.0.0",
            accessToken: "server-token",
            connections: [
                PlexServerConnection(
                    uri: URL(string: "http://\(host):32400")!,
                    local: true,
                    relay: false
                )
            ]
        )
    }
}

@MainActor
private func waitForPreviewLoad(
    on store: PlexServerPreviewStore,
    serverID: String,
    timeoutNanoseconds: UInt64 = 2_000_000_000
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        let state = store.state(for: serverID)
        if state.hasLoaded && state.isLoading == false {
            return
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
private func waitForPreviewFailure(
    on store: PlexServerPreviewStore,
    serverID: String,
    timeoutNanoseconds: UInt64 = 2_000_000_000
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        let state = store.state(for: serverID)
        if state.isLoading == false && state.errorMessage != nil {
            return
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

private func makePreviewStoreSession(responder: PreviewStoreResponder) -> URLSession {
    PreviewStoreMockURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PreviewStoreMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class PreviewStoreMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: PreviewStoreResponder?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        responder.respond(to: request) { result in
            switch result {
            case .success(let payload):
                self.client?.urlProtocol(self, didReceive: payload.response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: payload.data)
                self.client?.urlProtocolDidFinishLoading(self)
            case .failure(let error):
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private final class PreviewStoreResponder: @unchecked Sendable {
    private let lock = NSLock()
    private var previewRequestCounts: [String: Int] = [:]
    private var failingHosts: Set<String> = []

    func failFirstPreviewRequest(forHost host: String) {
        lock.lock()
        failingHosts.insert(host)
        lock.unlock()
    }

    func previewRequestCount(forHost host: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return previewRequestCounts[host, default: 0]
    }

    func respond(
        to request: URLRequest,
        completion: @escaping @Sendable (Result<(response: HTTPURLResponse, data: Data), Error>) -> Void
    ) {
        guard let url = request.url,
              let host = url.host else {
            completion(.failure(URLError(.badURL)))
            return
        }

        if url.path == "/library/sections/all" {
            completion(.success((
                response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: #"{"MediaContainer":{"Directory":[{"key":"1","title":"Movies","type":"movie"}]}}"#.data(using: .utf8)!
            )))
            return
        }

        if url.path == "/library/sections/1/all" {
            let requestNumber = incrementPreviewRequestCount(forHost: host)
            if shouldFailPreviewRequest(forHost: host, requestNumber: requestNumber) {
                completion(.success((
                    response: HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    data: Data()
                )))
                return
            }

            let payload = previewPayload(forHost: host)
            let delayNanoseconds: UInt64 = host == "plex.local" ? 250_000_000 : 20_000_000

            DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(delayNanoseconds))) {
                completion(.success((
                    response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data: payload
                )))
            }
            return
        }

        completion(.failure(URLError(.unsupportedURL)))
    }

    private func incrementPreviewRequestCount(forHost host: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        previewRequestCounts[host, default: 0] += 1
        return previewRequestCounts[host, default: 0]
    }

    private func shouldFailPreviewRequest(forHost host: String, requestNumber: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard failingHosts.contains(host), requestNumber == 1 else {
            return false
        }

        return true
    }

    private func previewPayload(forHost host: String) -> Data {
        let title = host == "plex.local" ? "First Server Movie" : "Second Server Movie"

        return #"""
        {
          "MediaContainer": {
            "Metadata": [
              {
                "ratingKey": "\#(host)-1",
                "title": "\#(title)",
                "addedAt": 1712452410,
                "thumb": "/library/metadata/\#(host)-1/thumb/1"
              }
            ]
          }
        }
        """#.data(using: .utf8)!
    }
}
