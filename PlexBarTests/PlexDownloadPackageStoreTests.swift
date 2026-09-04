import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexDownloadPackageStoreTests {
    @Test func publishesOnlyACompleteValidatedPackage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sourceData = Data("native-offline-media".utf8)
        let sourceURL = try fixture.makeDownloadedFile(data: sourceData)
        let completedAt = Date(timeIntervalSince1970: 1_788_134_400)

        let package = try await fixture.store.publish(
            identity: fixture.identity,
            title: "The Episode",
            mediaType: "episode",
            decisionData: fixture.decisionData,
            downloadedFileURL: sourceURL,
            mediaFileExtension: ".mp4",
            contentType: "video/mp4",
            completedAt: completedAt
        )

        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(package.id == fixture.identity.packageID)
        #expect(package.manifest.schemaVersion == 2)
        #expect(package.manifest.identity.accountID == 9)
        #expect(package.packageURL.lastPathComponent == "\(fixture.identity.packageID.uuidString).plexdownload")
        #expect(package.manifest.title == "The Episode")
        #expect(package.manifest.mediaFileName == "media.mp4")
        #expect(package.manifest.mediaByteCount == Int64(sourceData.count))
        #expect(package.manifest.completedAt == completedAt)
        #expect(try Data(contentsOf: package.mediaURL) == sourceData)
        #expect(try Data(contentsOf: package.decisionURL) == fixture.decisionData)

        let reconciliation = try await fixture.store.reconcile()
        #expect(reconciliation.packages == [package])
        #expect(reconciliation.integrityIssues.isEmpty)
        #expect(reconciliation.removedStagingPackageCount == 0)
    }

    @Test func rejectsInvalidOrMismatchedDecisionWithoutPublishing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let invalidSource = try fixture.makeDownloadedFile(data: Data("media".utf8))

        await #expect(throws: PlexDownloadPackageStoreError.self) {
            _ = try await fixture.store.publish(
                identity: fixture.identity,
                title: "Episode",
                mediaType: "episode",
                decisionData: Data(#"{"MediaContainer":{"Metadata":[]}}"#.utf8),
                downloadedFileURL: invalidSource,
                mediaFileExtension: "mp4",
                contentType: "video/mp4"
            )
        }

        #expect(FileManager.default.fileExists(atPath: invalidSource.path))
        let reconciliation = try await fixture.store.reconcile()
        #expect(reconciliation.packages.isEmpty)
        #expect(reconciliation.integrityIssues.isEmpty)
    }

    @Test func rejectsEmptyMediaWithoutPublishing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sourceURL = try fixture.makeDownloadedFile(data: Data())

        await #expect(throws: PlexDownloadPackageStoreError.invalidDownloadedFile) {
            _ = try await fixture.store.publish(
                identity: fixture.identity,
                title: "Episode",
                mediaType: "episode",
                decisionData: fixture.decisionData,
                downloadedFileURL: sourceURL,
                mediaFileExtension: "mp4",
                contentType: "video/mp4"
            )
        }

        let reconciliation = try await fixture.store.reconcile()
        #expect(reconciliation.packages.isEmpty)
        #expect(reconciliation.integrityIssues.isEmpty)
    }

    @Test func rejectsMediaMissingAServerPromisedEmbeddedSubtitle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sourceURL = try fixture.makeDownloadedFile(data: Data("not-an-mp4".utf8))

        await #expect(throws: PlexDownloadPackageStoreError.missingEmbeddedSubtitle) {
            _ = try await fixture.store.publish(
                identity: fixture.identity,
                title: "Episode",
                mediaType: "episode",
                decisionData: fixture.decisionWithEmbeddedSubtitleData,
                downloadedFileURL: sourceURL,
                mediaFileExtension: "mp4",
                contentType: "video/mp4"
            )
        }

        let reconciliation = try await fixture.store.reconcile()
        #expect(reconciliation.packages.isEmpty)
        #expect(reconciliation.integrityIssues.isEmpty)
    }

    @Test func replacementPublishesOnePackageWithTheNewMedia() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalData = Data("original-media".utf8)
        let replacementData = Data("replacement-media".utf8)

        _ = try await fixture.publish(mediaData: originalData, title: "Original")
        let replacement = try await fixture.publish(
            mediaData: replacementData,
            title: "Replacement"
        )

        #expect(replacement.manifest.title == "Replacement")
        #expect(try Data(contentsOf: replacement.mediaURL) == replacementData)
        let reconciliation = try await fixture.store.reconcile()
        #expect(reconciliation.packages.count == 1)
        #expect(reconciliation.packages.first?.id == fixture.identity.packageID)
        #expect(reconciliation.integrityIssues.isEmpty)
    }

    @Test func failedReplacementPreservesThePublishedPackage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalData = Data("original-media".utf8)
        let original = try await fixture.publish(mediaData: originalData, title: "Original")
        let failedSource = try fixture.makeDownloadedFile(data: Data("failed-media".utf8))

        await #expect(throws: PlexDownloadPackageStoreError.self) {
            _ = try await fixture.store.publish(
                identity: fixture.identity,
                title: "Replacement",
                mediaType: "episode",
                decisionData: Data("not-json".utf8),
                downloadedFileURL: failedSource,
                mediaFileExtension: "mp4",
                contentType: "video/mp4"
            )
        }

        let preserved = try #require(try await fixture.store.package(
            withID: fixture.identity.packageID
        ))
        #expect(preserved.manifest.title == original.manifest.title)
        #expect(try Data(contentsOf: preserved.mediaURL) == originalData)
    }

    @Test func reconciliationPurgesStagingButReportsCorruptionWithoutDeletingIt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try await fixture.publish(
            mediaData: Data("media".utf8),
            title: "Episode"
        )
        try Data("tampered-media-is-larger".utf8).write(to: package.mediaURL)
        let stagingURL = package.packageURL.deletingLastPathComponent()
            .appendingPathComponent(".staging-abandoned", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: false)

        let reconciliation = try await fixture.store.reconcile()

        #expect(reconciliation.packages.isEmpty)
        #expect(reconciliation.removedStagingPackageCount == 1)
        #expect(reconciliation.integrityIssues.count == 1)
        #expect(reconciliation.integrityIssues.first?.reason == .mediaSizeMismatch(
            expected: 5,
            actual: 24
        ))
        #expect(FileManager.default.fileExists(atPath: package.packageURL.path))
        #expect(!FileManager.default.fileExists(atPath: stagingURL.path))
        await #expect(throws: PlexDownloadPackageStoreError.self) {
            _ = try await fixture.store.package(withID: fixture.identity.packageID)
        }
    }

    @Test func removalIsExactAndIdempotent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try await fixture.publish(mediaData: Data("media".utf8), title: "Episode")

        try await fixture.store.removePackage(withID: fixture.identity.packageID)
        try await fixture.store.removePackage(withID: fixture.identity.packageID)

        #expect(try await fixture.store.package(withID: fixture.identity.packageID) == nil)
    }

    @Test func artworkAndOfflineMetadataRemainPartOfTheValidatedPackage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let artworkData = Data("validated-poster-bytes".utf8)
        _ = try await fixture.publish(
            mediaData: Data("media".utf8),
            title: "The Episode"
        )

        let package = try await fixture.store.installArtwork(
            artworkData,
            for: fixture.identity.packageID
        )
        let media = try #require(try await fixture.store.offlineMedia().first)

        #expect(package.manifest.artworkFileName == PlexDownloadPackageStore.artworkFileName)
        #expect(try Data(contentsOf: #require(package.artworkURL)) == artworkData)
        #expect(media.package == package)
        #expect(media.item.ratingKey == fixture.identity.ratingKey)
        #expect(media.item.key == fixture.identity.metadataKey)
        #expect(media.item.title == "Episode")

        let reconciliation = try await fixture.store.reconcile()
        #expect(reconciliation.packages == [package])
        #expect(reconciliation.integrityIssues.isEmpty)
    }

    @Test func exactOfflineMediaLookupRevalidatesThePackage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try await fixture.publish(
            mediaData: Data("media".utf8),
            title: "The Episode"
        )

        let media = try #require(try await fixture.store.offlineMedia(
            withID: fixture.identity.packageID
        ))
        #expect(media.package == package)
        #expect(media.item.ratingKey == fixture.identity.ratingKey)

        try Data().write(to: package.mediaURL)

        await #expect(throws: PlexDownloadPackageStoreError.invalidPackage) {
            _ = try await fixture.store.offlineMedia(withID: fixture.identity.packageID)
        }
    }

    @Test func offlineMediaLookupIsScopedToTheExactAccountAndServer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = try await fixture.publish(
            mediaData: Data("media".utf8),
            title: "The Episode"
        )

        let owned = try await fixture.store.offlineMedia(
            accountID: 9,
            serverIdentifier: "server-id"
        )
        let wrongAccount = try await fixture.store.offlineMedia(
            accountID: 10,
            serverIdentifier: "server-id"
        )
        let wrongServer = try await fixture.store.offlineMedia(
            accountID: 9,
            serverIdentifier: "other-server"
        )

        #expect(owned.map(\.id) == [package.id])
        #expect(wrongAccount.isEmpty)
        #expect(wrongServer.isEmpty)
        #expect(try await fixture.store.offlineMedia(
            withID: package.id,
            accountID: 9,
            serverIdentifier: "server-id"
        )?.id == package.id)
        #expect(try await fixture.store.offlineMedia(
            withID: package.id,
            accountID: 10,
            serverIdentifier: "server-id"
        ) == nil)
    }

    @Test func legacyUnownedIdentityFailsClosedWithoutPublishing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let identity = try JSONDecoder().decode(
            PlexDownloadPackageIdentity.self,
            from: Data(#"{"packageID":"37A0DC71-EB7D-4F12-8C62-171924BF6136","serverIdentifier":"server-id","queueID":7,"queueItemID":11,"metadataKey":"/library/metadata/42","ratingKey":"42"}"#.utf8)
        )

        #expect(identity.accountID == nil)
        await #expect(throws: PlexDownloadPackageStoreError.invalidIdentity) {
            try await fixture.store.validateMetadata(
                identity: identity,
                title: "Episode",
                decisionData: fixture.decisionData,
                mediaFileExtension: "mp4"
            )
        }
        #expect(try await fixture.store.reconcile().packages.isEmpty)
    }

    @Test func rejectsUnsafeIdentityExtensionsAndSymbolicLinkSources() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let targetURL = try fixture.makeDownloadedFile(data: Data("media".utf8))
        let symbolicLinkURL = fixture.rootURL.appendingPathComponent("media-link")
        try FileManager.default.createSymbolicLink(
            at: symbolicLinkURL,
            withDestinationURL: targetURL
        )

        await #expect(throws: PlexDownloadPackageStoreError.self) {
            _ = try await fixture.store.publish(
                identity: fixture.identity,
                title: "Episode",
                mediaType: "episode",
                decisionData: fixture.decisionData,
                downloadedFileURL: symbolicLinkURL,
                mediaFileExtension: "mp4",
                contentType: "video/mp4"
            )
        }
        await #expect(throws: PlexDownloadPackageStoreError.self) {
            _ = try await fixture.store.publish(
                identity: fixture.identity,
                title: "Episode",
                mediaType: "episode",
                decisionData: fixture.decisionData,
                downloadedFileURL: targetURL,
                mediaFileExtension: "../../movie",
                contentType: "video/mp4"
            )
        }

        let invalidIdentity = PlexDownloadPackageIdentity(
            accountID: 9,
            serverIdentifier: "server-id",
            queueID: 7,
            queueItemID: 11,
            metadataKey: "/library/metadata/../outside",
            ratingKey: "42"
        )
        await #expect(throws: PlexDownloadPackageStoreError.self) {
            _ = try await fixture.store.publish(
                identity: invalidIdentity,
                title: "Episode",
                mediaType: "episode",
                decisionData: fixture.decisionData,
                downloadedFileURL: targetURL,
                mediaFileExtension: "mp4",
                contentType: "video/mp4"
            )
        }

        #expect(FileManager.default.fileExists(atPath: targetURL.path))
        let reconciliation = try await fixture.store.reconcile()
        #expect(reconciliation.packages.isEmpty)
        #expect(reconciliation.integrityIssues.isEmpty)
    }
}

private struct Fixture {
    let rootURL: URL
    let store: PlexDownloadPackageStore
    let identity = PlexDownloadPackageIdentity(
        packageID: UUID(uuidString: "37A0DC71-EB7D-4F12-8C62-171924BF6136")!,
        accountID: 9,
        serverIdentifier: "server-id",
        queueID: 7,
        queueItemID: 11,
        metadataKey: "/library/metadata/42",
        ratingKey: "42"
    )

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlexDownloadPackageStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = PlexDownloadPackageStore(rootURL: rootURL)
    }

    var decisionData: Data {
        Data(#"{"MediaContainer":{"allowSync":"1","Metadata":[{"ratingKey":"42","key":"/library/metadata/42","title":"Episode","type":"episode","Media":[]}]}}"#.utf8)
    }

    var decisionWithEmbeddedSubtitleData: Data {
        Data(#"{"MediaContainer":{"allowSync":"1","Metadata":[{"ratingKey":"42","key":"/library/metadata/42","title":"Episode","type":"episode","Media":[{"Part":[{"Stream":[{"streamType":3,"codec":"mov_text","selected":true,"decision":"transcode","location":"embedded"}]}]}]}]}}"#.utf8)
    }

    func makeDownloadedFile(data: Data) throws -> URL {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let url = rootURL.appendingPathComponent("download-\(UUID().uuidString).tmp")
        try data.write(to: url)
        return url
    }

    func publish(mediaData: Data, title: String) async throws -> PlexDownloadPackage {
        let sourceURL = try makeDownloadedFile(data: mediaData)
        return try await store.publish(
            identity: identity,
            title: title,
            mediaType: "episode",
            decisionData: decisionData,
            downloadedFileURL: sourceURL,
            mediaFileExtension: "mp4",
            contentType: "video/mp4"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
