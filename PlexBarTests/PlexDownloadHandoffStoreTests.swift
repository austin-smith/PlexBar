import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexDownloadHandoffStoreTests {
    @Test func atomicallyAcceptsAndRestoresACompletedHTTPDownload() throws {
        let fixture = try HandoffFixture()
        defer { fixture.remove() }
        let mediaData = Data("completed-media".utf8)
        let temporaryURL = try fixture.makeFile(data: mediaData)

        let result = fixture.store.accept(
            temporaryFileURL: temporaryURL,
            transferID: fixture.transferID,
            response: fixture.response()
        )
        let handoff = try result.get()

        #expect(!FileManager.default.fileExists(atPath: temporaryURL.path))
        #expect(handoff.manifest.transferID == fixture.transferID)
        #expect(handoff.manifest.statusCode == 200)
        #expect(handoff.manifest.contentType == "video/mp4")
        #expect(handoff.manifest.suggestedFileExtension == "mp4")
        #expect(try Data(contentsOf: handoff.mediaURL) == mediaData)
        #expect(try fixture.store.handoff(for: fixture.transferID).get() == handoff)
    }

    @Test func rejectsErrorResponsesAndSymbolicLinksWithoutConsumingTheSource() throws {
        let fixture = try HandoffFixture()
        defer { fixture.remove() }
        let temporaryURL = try fixture.makeFile(data: Data("error-page".utf8))

        let statusResult = fixture.store.accept(
            temporaryFileURL: temporaryURL,
            transferID: fixture.transferID,
            response: fixture.response(statusCode: 401)
        )
        #expect(statusResult == .failure(.serverStatus(401)))
        #expect(FileManager.default.fileExists(atPath: temporaryURL.path))

        let linkURL = fixture.rootURL.appendingPathComponent("download-link")
        try FileManager.default.createSymbolicLink(
            at: linkURL,
            withDestinationURL: temporaryURL
        )
        let linkResult = fixture.store.accept(
            temporaryFileURL: linkURL,
            transferID: fixture.transferID,
            response: fixture.response()
        )
        #expect(linkResult == .failure(.invalidTemporaryFile))
        #expect(FileManager.default.fileExists(atPath: temporaryURL.path))
    }

    @Test func reconciliationRemovesOnlyPrivateStagingAndOrphanHandoffs() throws {
        let fixture = try HandoffFixture()
        defer { fixture.remove() }
        let validID = fixture.transferID
        let orphanID = UUID()
        _ = try fixture.store.accept(
            temporaryFileURL: fixture.makeFile(data: Data("valid".utf8)),
            transferID: validID,
            response: fixture.response()
        ).get()
        _ = try fixture.store.accept(
            temporaryFileURL: fixture.makeFile(data: Data("orphan".utf8)),
            transferID: orphanID,
            response: fixture.response()
        ).get()
        let incomingURL = fixture.rootURL.appendingPathComponent("Incoming", isDirectory: true)
        let stagingURL = incomingURL.appendingPathComponent(".staging-abandoned", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        let unrelatedURL = incomingURL.appendingPathComponent("keep-me")
        try Data("unrelated".utf8).write(to: unrelatedURL)

        let removed = try fixture.store.reconcile(validTransferIDs: [validID])

        #expect(removed == 2)
        #expect(try fixture.store.handoff(for: validID).get() != nil)
        #expect(try fixture.store.handoff(for: orphanID).get() == nil)
        #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }
}

private struct HandoffFixture {
    let rootURL: URL
    let transferID = UUID(uuidString: "8AE467A6-15C8-4AF9-8C9B-71EE9F6F387D")!
    let store: PlexDownloadHandoffStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlexDownloadHandoffStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = PlexDownloadHandoffStore(rootURL: rootURL)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func makeFile(data: Data) throws -> URL {
        let url = rootURL.appendingPathComponent("temporary-\(UUID().uuidString)")
        try data.write(to: url)
        return url
    }

    func response(statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://plex.test/downloadQueue/7/item/11/media")!,
            statusCode: statusCode,
            httpVersion: "HTTP/2",
            headerFields: [
                "Content-Type": "video/mp4",
                "Content-Disposition": "attachment; filename=episode.mp4",
            ]
        )!
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
