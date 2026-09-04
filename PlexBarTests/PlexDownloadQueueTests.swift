import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexDownloadQueueTests {
    @Test func createsAndFetchesTheClientScopedQueue() async throws {
        let capture = RequestCapture()
        let session = makeDownloadQueueMockSession { request in
            capture.record(request)
            return try response(
                for: request,
                data: Data(#"{"MediaContainer":{"size":1,"DownloadQueue":[{"id":7,"status":"done","itemCount":0}]}}"#.utf8)
            )
        }
        let client = PlexAPIClient(session: session)

        let created = try await client.fetchOrCreateDownloadQueue(using: configuration)
        let fetched = try await client.fetchDownloadQueue(queueID: 7, using: configuration)

        #expect(created == PlexDownloadQueue(id: 7, status: .done, itemCount: 0))
        #expect(fetched == created)
        #expect(capture.requests.map(\.httpMethod) == ["POST", "GET"])
        #expect(capture.requests.compactMap(\.url?.path) == [
            "/downloadQueue",
            "/downloadQueue/7",
        ])
        #expect(capture.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "X-Plex-Token") == "server-token"
        })
    }

    @Test func addsMetadataWithOnlyTheExplicitDecisionContract() async throws {
        let capture = RequestCapture()
        let session = makeDownloadQueueMockSession { request in
            capture.record(request)
            return try response(
                for: request,
                data: Data(#"{"MediaContainer":{"size":2,"AddedQueueItems":[{"key":"/library/metadata/42","id":11},{"key":"/library/metadata/43","id":12}]}}"#.utf8)
            )
        }
        let decision = PlexDownloadDecisionParameters(
            mediaPath: "/library/metadata/42",
            mediaIndex: 0,
            partIndex: 0,
            deliveryProtocol: .http,
            allowsDirectPlay: true,
            allowsDirectStream: true,
            allowsDirectStreamAudio: true,
            subtitleMode: .sidecar,
            advancedSubtitleMode: .text,
            videoBitrate: 8_000,
            videoQuality: 99,
            videoResolution: "1920x1080",
            sessionIdentifier: "download-session",
            clientProfileName: "generic",
            clientProfileExtra: "profile-contract"
        )

        let added = try await PlexAPIClient(session: session).addToDownloadQueue(
            keys: ["/library/metadata/42", "/library/metadata/43"],
            queueID: 7,
            decision: decision,
            using: configuration
        )

        #expect(added == [
            PlexAddedDownloadQueueItem(key: "/library/metadata/42", id: 11),
            PlexAddedDownloadQueueItem(key: "/library/metadata/43", id: 12),
        ])
        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "POST")
        #expect(components.path == "/downloadQueue/7/add")
        #expect(queryValue("keys", in: components) == "/library/metadata/42,/library/metadata/43")
        #expect(queryValue("path", in: components) == "/library/metadata/42")
        #expect(queryValue("mediaIndex", in: components) == "0")
        #expect(queryValue("partIndex", in: components) == "0")
        #expect(queryValue("protocol", in: components) == "http")
        #expect(queryValue("directPlay", in: components) == "1")
        #expect(queryValue("directStream", in: components) == "1")
        #expect(queryValue("directStreamAudio", in: components) == "1")
        #expect(queryValue("subtitles", in: components) == "sidecar")
        #expect(queryValue("advancedSubtitles", in: components) == "text")
        #expect(queryValue("videoBitrate", in: components) == "8000")
        #expect(queryValue("videoQuality", in: components) == "99")
        #expect(queryValue("videoResolution", in: components) == "1920x1080")
        #expect(queryValue("musicBitrate", in: components) == nil)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Session-Identifier") == "download-session")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Profile-Name") == "generic")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Profile-Extra") == "profile-contract")
    }

    @Test func sendsTheDocumentedMultipartJoinIndex() async throws {
        let capture = RequestCapture()
        let session = makeDownloadQueueMockSession { request in
            capture.record(request)
            return try response(
                for: request,
                data: Data(#"{"MediaContainer":{"size":1,"AddedQueueItems":[{"key":"/library/metadata/42","id":11}]}}"#.utf8)
            )
        }
        let decision = PlexDownloadDecisionParameters(
            mediaPath: "/library/metadata/42",
            mediaIndex: 0,
            partIndex: -1,
            deliveryProtocol: .http,
            allowsDirectPlay: false,
            allowsDirectStream: false,
            allowsDirectStreamAudio: false,
            videoQuality: 99,
            sessionIdentifier: "multipart-download"
        )

        _ = try await PlexAPIClient(session: session).addToDownloadQueue(
            keys: ["/library/metadata/42"],
            queueID: 7,
            decision: decision,
            using: configuration
        )

        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(queryValue("mediaIndex", in: components) == "0")
        #expect(queryValue("partIndex", in: components) == "-1")
        #expect(queryValue("directPlay", in: components) == "0")
        #expect(queryValue("directStream", in: components) == "0")
        #expect(queryValue("directStreamAudio", in: components) == "0")
    }

    @Test func decodesAuthoritativeProcessingStateAndDecisionFacts() async throws {
        let capture = RequestCapture()
        let session = makeDownloadQueueMockSession { request in
            capture.record(request)
            return try response(for: request, data: Self.processingItemsData)
        }

        let items = try await PlexAPIClient(session: session).fetchDownloadQueueItems(
            queueID: 7,
            itemIDs: [11, 12],
            using: configuration
        )

        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.id == 11)
        #expect(item.queueID == 7)
        #expect(item.key == "/library/metadata/42")
        #expect(item.status == .processing)
        #expect(item.decisionResult?.generalDecisionCode == 1001)
        #expect(item.decisionResult?.directPlayDecisionCode == 3001)
        #expect(item.transcodeSession?.progress == 47.5)
        #expect(item.transcodeSession?.size == 1_048_576)
        #expect(item.transcodeSession?.protocol == "http")
        #expect(capture.request?.url?.path == "/downloadQueue/7/items/11,12")
    }

    @Test func deletesAndRestartsExactQueueItems() async throws {
        let capture = RequestCapture()
        let session = makeDownloadQueueMockSession { request in
            capture.record(request)
            return try response(for: request, data: Data())
        }
        let client = PlexAPIClient(session: session)

        try await client.deleteDownloadQueueItems(
            queueID: 7,
            itemIDs: [11, 12],
            using: configuration
        )
        try await client.restartDownloadQueueItems(
            queueID: 7,
            itemIDs: [11, 12],
            using: configuration
        )

        #expect(capture.requests.map(\.httpMethod) == ["DELETE", "POST"])
        #expect(capture.requests.compactMap(\.url?.path) == [
            "/downloadQueue/7/items/11,12",
            "/downloadQueue/7/items/11,12/restart",
        ])
    }

    @Test func decodesTheQueueItemDecisionAndBuildsAStreamingMediaRequest() async throws {
        let capture = RequestCapture()
        let session = makeDownloadQueueMockSession { request in
            capture.record(request)
            return try response(for: request, data: Self.decisionData)
        }
        let client = PlexAPIClient(session: session)

        let document = try await client.fetchDownloadQueueDecisionDocument(
            queueID: 7,
            itemID: 11,
            using: configuration
        )
        let decision = document.decision
        let mediaRequest = try client.downloadQueueMediaRequest(
            queueID: 7,
            itemID: 11,
            using: configuration
        )

        #expect(decision.allowSync == true)
        #expect(decision.generalDecisionCode == 1000)
        #expect(decision.directPlayDecisionCode == 1000)
        #expect(decision.transcodeDecisionCode == nil)
        #expect(decision.resourceSession == "resource-session")
        #expect(decision.metadata.map(\.ratingKey) == ["42"])
        #expect(document.data == Self.decisionData)
        #expect(capture.request?.url?.path == "/downloadQueue/7/item/11/decision")
        #expect(mediaRequest.httpMethod == "GET")
        #expect(mediaRequest.url?.path == "/downloadQueue/7/item/11/media")
        #expect(mediaRequest.value(forHTTPHeaderField: "Accept") == nil)
        #expect(mediaRequest.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
    }

    @Test func rejectsInvalidQueueIdentifiersAndExternalMetadataKeys() async throws {
        let client = PlexAPIClient()
        let decision = PlexDownloadDecisionParameters()

        await #expect(throws: PlexAPIError.self) {
            _ = try await client.fetchDownloadQueue(queueID: 0, using: configuration)
        }
        await #expect(throws: PlexAPIError.self) {
            _ = try await client.addToDownloadQueue(
                keys: ["https://outside.example/library/metadata/42"],
                queueID: 7,
                decision: decision,
                using: configuration
            )
        }
        await #expect(throws: PlexAPIError.self) {
            _ = try await client.fetchDownloadQueueItems(
                queueID: 7,
                itemIDs: [],
                using: configuration
            )
        }
        #expect(throws: PlexAPIError.self) {
            _ = try client.downloadQueueMediaRequest(
                queueID: 7,
                itemID: -1,
                using: configuration
            )
        }

        await #expect(throws: PlexAPIError.self) {
            _ = try await client.addToDownloadQueue(
                keys: ["/library/metadata/42"],
                queueID: 7,
                decision: PlexDownloadDecisionParameters(videoQuality: 100),
                using: configuration
            )
        }
        await #expect(throws: PlexAPIError.self) {
            _ = try await client.addToDownloadQueue(
                keys: ["/library/metadata/42"],
                queueID: 7,
                decision: PlexDownloadDecisionParameters(videoResolution: "1080p"),
                using: configuration
            )
        }
    }

    private var configuration: PlexConnectionConfiguration {
        PlexConnectionConfiguration(
            serverURL: URL(string: "https://plex.test:32400")!,
            token: "server-token",
            clientContext: PlexClientContext(clientIdentifier: "client-123"),
            serverIdentifier: "server-id"
        )
    }

    private static let processingItemsData = Data(#"""
    {
      "MediaContainer": {
        "size": 1,
        "DownloadQueueItem": [
          {
            "id": 11,
            "queueId": 7,
            "key": "/library/metadata/42",
            "status": "processing",
            "DecisionResult": {
              "generalDecisionCode": 1001,
              "generalDecisionText": "Direct play not available; Conversion OK.",
              "directPlayDecisionCode": 3001,
              "directPlayDecisionText": "Not enough bandwidth for direct play of this item.",
              "transcodeDecisionCode": 1001,
              "transcodeDecisionText": "Direct play not available; Conversion OK."
            },
            "TranscodeSession": {
              "key": "/transcode/sessions/download",
              "throttled": false,
              "complete": false,
              "progress": 47.5,
              "size": 1048576,
              "speed": 8.25,
              "error": false,
              "duration": 300000000,
              "context": "streaming",
              "sourceVideoCodec": "h264",
              "sourceAudioCodec": "aac",
              "protocol": "http",
              "transcodeHwRequested": true,
              "transcodeHwFullPipeline": false
            }
          }
        ]
      }
    }
    """#.utf8)

    private static let decisionData = Data(#"""
    {
      "MediaContainer": {
        "allowSync": "1",
        "generalDecisionCode": "1000",
        "generalDecisionText": "Direct play OK.",
        "directPlayDecisionCode": 1000,
        "directPlayDecisionText": "Direct play OK.",
        "resourceSession": "resource-session",
        "Metadata": [
          {
            "ratingKey": "42",
            "key": "/library/metadata/42",
            "title": "Episode",
            "type": "episode",
            "Media": []
          }
        ]
      }
    }
    """#.utf8)
}

private func makeDownloadQueueMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    DownloadQueueMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DownloadQueueMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func response(
    for request: URLRequest,
    statusCode: Int = 200,
    data: Data
) throws -> (HTTPURLResponse, Data) {
    let response = try #require(HTTPURLResponse(
        url: request.url!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    ))
    return (response, data)
}

private func queryValue(_ name: String, in components: URLComponents) -> String? {
    components.queryItems?.first(where: { $0.name == name })?.value
}

private final class DownloadQueueMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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
