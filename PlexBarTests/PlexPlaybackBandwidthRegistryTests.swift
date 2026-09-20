@testable import PlexClientKit
import Foundation
import Testing
@testable import PlexBar

struct PlexPlaybackBandwidthRegistryTests {
    @Test func newestExactSamplePersistsPerServerAcrossRegistryInstances() async throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let olderCandidate = makeSample(
            byteCount: 1_000_000,
            startedAt: 100,
            endedAt: 102
        )
        let older = try #require(olderCandidate)
        let newerCandidate = makeSample(
            byteCount: 3_000_000,
            startedAt: 200,
            endedAt: 202
        )
        let newer = try #require(newerCandidate)
        let registry = PlexPlaybackBandwidthRegistry(rootURL: rootURL)

        try await registry.record(newer, for: "server-a")
        try await registry.record(older, for: "server-a")
        try await registry.record(older, for: "server-b")

        let reloadedRegistry = PlexPlaybackBandwidthRegistry(rootURL: rootURL)
        #expect(try await reloadedRegistry.record(for: "server-a") ==
            PlexPlaybackBandwidthRecord(serverIdentifier: "server-a", sample: newer))
        #expect(try await reloadedRegistry.record(for: "server-b") ==
            PlexPlaybackBandwidthRecord(serverIdentifier: "server-b", sample: older))
        #expect(try await reloadedRegistry.records().map(\.serverIdentifier) == [
            "server-a",
            "server-b",
        ])
    }

    @Test func registryRetainsOnlyTheMostRecentlyMeasuredServers() async throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let registry = PlexPlaybackBandwidthRegistry(rootURL: rootURL)

        for index in 0...PlexPlaybackBandwidthRegistry.retainedServerLimit {
            let startedAt = TimeInterval(index * 2)
            let endedAt = TimeInterval(index * 2 + 1)
            let candidate = makeSample(
                byteCount: 1_000,
                startedAt: startedAt,
                endedAt: endedAt
            )
            let bandwidthSample = try #require(candidate)
            try await registry.record(bandwidthSample, for: "server-\(index)")
        }

        let records = try await registry.records()
        #expect(records.count == PlexPlaybackBandwidthRegistry.retainedServerLimit)
        #expect(!records.contains { $0.serverIdentifier == "server-0" })
        #expect(records.first?.serverIdentifier ==
            "server-\(PlexPlaybackBandwidthRegistry.retainedServerLimit)")
    }

    @Test func malformedRegistryFailsClosedWithoutOverwritingIt() async throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let registryURL = rootURL.appendingPathComponent("bandwidth-history.json")
        let originalData = Data("not-json".utf8)
        try originalData.write(to: registryURL)
        let registry = PlexPlaybackBandwidthRegistry(rootURL: rootURL)

        await #expect(throws: PlexPlaybackBandwidthRegistryError.invalidRegistry) {
            try await registry.records()
        }
        #expect(try Data(contentsOf: registryURL) == originalData)
    }

    @Test func blankServerIdentityIsRejectedBeforePersistence() async throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let registry = PlexPlaybackBandwidthRegistry(rootURL: rootURL)
        let candidate = makeSample(
            byteCount: 1_000,
            startedAt: 0,
            endedAt: 1
        )
        let bandwidthSample = try #require(candidate)

        await #expect(throws: PlexPlaybackBandwidthRegistryError.invalidServerIdentifier) {
            try await registry.record(bandwidthSample, for: "  ")
        }
        #expect(!FileManager.default.fileExists(atPath: rootURL.path))
    }

    private func makeSample(
        byteCount: Int64,
        startedAt: TimeInterval,
        endedAt: TimeInterval
    ) -> PlexPlaybackBandwidthSample? {
        PlexPlaybackBandwidthSample(
            byteCount: byteCount,
            responseStartTime: Date(timeIntervalSince1970: startedAt),
            responseEndTime: Date(timeIntervalSince1970: endedAt),
            wasReadFromCache: false,
            hadError: false
        )
    }

    private func temporaryRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PlexPlaybackBandwidthRegistryTests-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}
