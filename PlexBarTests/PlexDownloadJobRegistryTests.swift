@testable import PlexClientKit
import Foundation
import Testing
@testable import PlexBar

@Suite
struct PlexDownloadJobRegistryTests {
    @Test func durableJobAndOfflineProgressRoundTripWithoutConnectionSecrets() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PlexDownloadJobRegistryTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let identity = PlexDownloadPackageIdentity(
            packageID: UUID(uuidString: "AD460C2A-9E97-48CB-BC84-57B03BFB4128")!,
            accountID: 9,
            serverIdentifier: "server-id",
            queueID: 7,
            queueItemID: 11,
            metadataKey: "/library/metadata/42",
            ratingKey: "42"
        )
        let job = PlexDownloadJob(
            id: identity.packageID,
            accountID: 9,
            packageIdentity: identity,
            libraryID: "1",
            title: "Episode",
            mediaType: "episode",
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
            decisionParameters: PlexDownloadDecisionParameters(
                mediaPath: identity.metadataKey,
                mediaIndex: 0,
                partIndex: 0,
                deliveryProtocol: .http,
                allowsDirectPlay: true,
                sessionIdentifier: "download-session"
            ),
            createdAt: Date(timeIntervalSince1970: 1_777_777_777),
            updatedAt: Date(timeIntervalSince1970: 1_777_777_778),
            state: .paused,
            serverPreparationProgress: 1,
            transferID: UUID(uuidString: "23A8B289-579D-4E40-B23D-B27035BD930A"),
            errorMessage: nil
        )
        let jobRegistry = PlexDownloadJobRegistry(rootURL: rootURL)
        try await jobRegistry.save(job)

        let restoredJobs = try await PlexDownloadJobRegistry(rootURL: rootURL).jobs()
        #expect(restoredJobs == [job])

        let rawRegistry = try String(
            contentsOf: rootURL.appendingPathComponent("Jobs/registry.json"),
            encoding: .utf8
        )
        #expect(!rawRegistry.contains("X-Plex-Token"))
        #expect(!rawRegistry.contains("https://"))

        let playback = PlexOfflinePlaybackRecord(
            packageID: identity.packageID,
            accountID: 9,
            serverIdentifier: identity.serverIdentifier,
            ratingKey: identity.ratingKey,
            baselineViewOffset: 12_000,
            baselineViewCount: 0,
            position: 44_000,
            duration: 60_000,
            state: .paused,
            updatedAt: Date(timeIntervalSince1970: 1_777_777_779),
            needsSync: true
        )
        let playbackRegistry = PlexOfflinePlaybackRegistry(rootURL: rootURL)
        try await playbackRegistry.save(playback)

        let restoredPlayback = try await PlexOfflinePlaybackRegistry(rootURL: rootURL)
            .record(for: identity.packageID)
        #expect(restoredPlayback == playback)
    }

    @Test func multipartJoinSelectionSurvivesJobPersistence() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PlexDownloadJobRegistryTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let identity = PlexDownloadPackageIdentity(
            accountID: 9,
            serverIdentifier: "server-id",
            queueID: 7,
            queueItemID: 11,
            metadataKey: "/library/metadata/42",
            ratingKey: "42"
        )
        let source = PlexPlaybackSource(mediaIndex: 1, partIndex: -1)
        let decisionParameters = PlexDownloadDecisionParameters(
            mediaPath: identity.metadataKey,
            mediaIndex: source.mediaIndex,
            partIndex: source.partIndex,
            deliveryProtocol: .http,
            allowsDirectPlay: false,
            allowsDirectStream: false,
            allowsDirectStreamAudio: false,
            sessionIdentifier: "multipart-download-session"
        )
        let job = PlexDownloadJob(
            id: identity.packageID,
            accountID: 9,
            packageIdentity: identity,
            libraryID: "1",
            title: "Multipart Movie",
            mediaType: "movie",
            source: source,
            decisionParameters: decisionParameters,
            createdAt: Date(timeIntervalSince1970: 1_777_777_777),
            updatedAt: Date(timeIntervalSince1970: 1_777_777_778),
            state: .waitingForServer,
            serverPreparationProgress: nil,
            transferID: nil,
            errorMessage: nil
        )

        let registry = PlexDownloadJobRegistry(rootURL: rootURL)
        try await registry.save(job)

        let restored = try #require(
            try await PlexDownloadJobRegistry(rootURL: rootURL).jobs().first
        )
        #expect(restored.source == source)
        #expect(restored.decisionParameters == decisionParameters)
        #expect(restored.source.partIndex == -1)
        #expect(restored.decisionParameters.partIndex == -1)
    }
}
