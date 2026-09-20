import Foundation
import ImageIO
import Testing
@testable import PlexBarStudio

@Suite struct StudioReferenceDownloadTests {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReferenceImageProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func downloadsAndNormalizesImageWithoutRequiringAFileExtension() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let file = try await StudioReferenceDownload.load(" https://reference.test/image?id=42 ", session: session)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(file.isFileURL)
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 1 && image.height == 1)
        #expect(CGImageSourceGetType(source) as String? == "public.png")
    }

    @Test func rejectsHTTPFailuresEvenWhenTheBodyIsAnImage() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await StudioReferenceDownload.load("https://reference.test/missing", session: session)
            Issue.record("An HTTP failure must not become a reference image.")
        } catch { #expect(error.localizedDescription.contains("HTTP 404")) }
    }

    @Test func rejectsWebPagesAndReportsConnectionFailures() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await StudioReferenceDownload.load("https://reference.test/page", session: session)
            Issue.record("A web page must not become a reference image.")
        } catch { #expect(error.localizedDescription.contains("direct image URL")) }
        do {
            _ = try await StudioReferenceDownload.load("https://reference.test/offline", session: session)
            Issue.record("A connection failure must be reported.")
        } catch { #expect((error as? URLError)?.code == .notConnectedToInternet) }
    }

    @Test func rejectsNonHTTPReferences() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        for address in ["", "poster.png", "file:///tmp/poster.png", "ftp://reference.test/image"] {
            do {
                _ = try await StudioReferenceDownload.load(address, session: session)
                Issue.record("An invalid URL must be rejected: \(address)")
            } catch { #expect(error.localizedDescription.contains("HTTP or HTTPS")) }
        }
    }
}

private final class ReferenceImageProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: url.path == "/missing" ? 404 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: url.path == "/page" ? Data("<html>A web page</html>".utf8) : image)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
