import PlexModels
import Foundation

struct PlexPlaybackBandwidthRecord: Codable, Equatable, Identifiable, Sendable {
    let serverIdentifier: String
    let bitsPerSecond: Double
    let measuredAt: Date
    let byteCount: Int64
    let transferDuration: TimeInterval

    var id: String { serverIdentifier }

    init(
        serverIdentifier: String,
        sample: PlexPlaybackBandwidthSample
    ) {
        self.serverIdentifier = serverIdentifier
        bitsPerSecond = sample.bitsPerSecond
        measuredAt = sample.measuredAt
        byteCount = sample.byteCount
        transferDuration = sample.transferDuration
    }
}

actor PlexPlaybackBandwidthRegistry {
    private struct Document: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let records: [PlexPlaybackBandwidthRecord]
    }

    static let retainedServerLimit = 32

    private let rootURL: URL
    private var cachedRecords: [String: PlexPlaybackBandwidthRecord]?

    init(rootURL: URL = PlexPlaybackBandwidthRegistry.defaultRootURL()) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func defaultRootURL() -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent(AppConstants.appName, isDirectory: true)
            .appendingPathComponent("Playback", isDirectory: true)
    }

    func record(
        _ sample: PlexPlaybackBandwidthSample,
        for serverIdentifier: String
    ) throws {
        guard let serverIdentifier = serverIdentifier.nilIfBlank else {
            throw PlexPlaybackBandwidthRegistryError.invalidServerIdentifier
        }

        let record = PlexPlaybackBandwidthRecord(
            serverIdentifier: serverIdentifier,
            sample: sample
        )
        var records = try loadIfNeeded()
        if let existing = records[serverIdentifier] {
            guard record.measuredAt >= existing.measuredAt,
                  record != existing else {
                return
            }
        }

        records[serverIdentifier] = record
        if records.count > Self.retainedServerLimit {
            let identifiersToRemove = records.values
                .sorted {
                    if $0.measuredAt != $1.measuredAt {
                        return $0.measuredAt < $1.measuredAt
                    }
                    return $0.serverIdentifier < $1.serverIdentifier
                }
                .prefix(records.count - Self.retainedServerLimit)
                .map(\.serverIdentifier)
            for identifier in identifiersToRemove {
                records[identifier] = nil
            }
        }

        try persist(records)
        cachedRecords = records
    }

    func record(for serverIdentifier: String) throws -> PlexPlaybackBandwidthRecord? {
        guard let serverIdentifier = serverIdentifier.nilIfBlank else {
            throw PlexPlaybackBandwidthRegistryError.invalidServerIdentifier
        }
        return try loadIfNeeded()[serverIdentifier]
    }

    func records() throws -> [PlexPlaybackBandwidthRecord] {
        try loadIfNeeded().values.sorted {
            if $0.measuredAt != $1.measuredAt {
                return $0.measuredAt > $1.measuredAt
            }
            return $0.serverIdentifier < $1.serverIdentifier
        }
    }

    private func loadIfNeeded() throws -> [String: PlexPlaybackBandwidthRecord] {
        if let cachedRecords {
            return cachedRecords
        }
        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            cachedRecords = [:]
            return [:]
        }

        let document: Document
        do {
            document = try Self.decoder.decode(
                Document.self,
                from: Data(contentsOf: registryURL)
            )
        } catch {
            throw PlexPlaybackBandwidthRegistryError.invalidRegistry
        }
        guard document.schemaVersion == Document.currentSchemaVersion,
              document.records.count <= Self.retainedServerLimit,
              Set(document.records.map(\.serverIdentifier)).count == document.records.count,
              document.records.allSatisfy(Self.isValid) else {
            throw PlexPlaybackBandwidthRegistryError.invalidRegistry
        }

        let records = Dictionary(
            uniqueKeysWithValues: document.records.map { ($0.serverIdentifier, $0) }
        )
        cachedRecords = records
        return records
    }

    private func persist(_ records: [String: PlexPlaybackBandwidthRecord]) throws {
        do {
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
            let document = Document(
                schemaVersion: Document.currentSchemaVersion,
                records: records.values.sorted {
                    $0.serverIdentifier < $1.serverIdentifier
                }
            )
            try Self.encoder.encode(document).write(to: registryURL, options: .atomic)
        } catch {
            throw PlexPlaybackBandwidthRegistryError.registryUnavailable
        }
    }

    private var registryURL: URL {
        rootURL.appendingPathComponent("bandwidth-history.json")
    }

    private static func isValid(_ record: PlexPlaybackBandwidthRecord) -> Bool {
        record.serverIdentifier.nilIfBlank != nil
            && record.bitsPerSecond.isFinite
            && record.bitsPerSecond > 0
            && record.byteCount > 0
            && record.transferDuration.isFinite
            && record.transferDuration > 0
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum PlexPlaybackBandwidthRegistryError: LocalizedError, Equatable {
    case invalidServerIdentifier
    case invalidRegistry
    case registryUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidServerIdentifier:
            "Plex did not provide a valid server identity for this bandwidth sample."
        case .invalidRegistry:
            "The saved playback bandwidth history is invalid."
        case .registryUnavailable:
            "PlexBar could not save playback bandwidth history."
        }
    }
}
