import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PlexBar

@Suite(.serialized)
struct PlexPlaybackPreviewClientTests {
    @Test func requestsTheDocumentedPartTimestampWithHeaderAuthentication() async throws {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try previewImage().image, nil)
        try #require(CGImageDestinationFinalize(destination))
        let jpeg = data as Data
        let session = previewMockSession { request in
            #expect(request.url?.path == "/library/parts/20/indexes/sd/31000")
            #expect(request.url?.query == nil)
            #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "fixture-token")
            #expect(request.value(forHTTPHeaderField: "X-Plex-Pms-Api-Version") == "1.0.0")
            #expect(request.value(forHTTPHeaderField: "Accept") == "image/jpeg")
            return (200, "image/jpeg", jpeg)
        }
        defer { session.invalidateAndCancel() }
        let source = try previewSource()
        let result = try await PlexPlaybackPreviewClient(session: session).image(for: source.frame(at: 31.4), source: source)
        #expect(result.image.width == 2)
    }

    @Test(arguments: [404, 401, 403, 500])
    func distinguishesMissingIndexFromServerFailures(status: Int) async throws {
        let session = previewMockSession { _ in (status, "text/html", Data()) }
        defer { session.invalidateAndCancel() }
        let source = try previewSource()
        await #expect(throws: status == 404 ? PlexPlaybackPreviewError.noIndex : .httpStatus(status)) {
            try await PlexPlaybackPreviewClient(session: session).image(for: source.frame(at: 1), source: source)
        }
    }

    @Test func rejectsSuccessfulHTTPResponsesThatAreNotImages() async throws {
        let session = previewMockSession { _ in (200, "image/jpeg", Data("not a jpeg".utf8)) }
        defer { session.invalidateAndCancel() }
        let source = try previewSource()
        await #expect(throws: PlexPlaybackPreviewError.invalidImage) {
            try await PlexPlaybackPreviewClient(session: session).image(for: source.frame(at: 1), source: source)
        }
    }
}

private func previewMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (Int, String, Data)
) -> URLSession {
    PreviewMockURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PreviewMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class PreviewMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, String, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, type, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": type])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {}
}
