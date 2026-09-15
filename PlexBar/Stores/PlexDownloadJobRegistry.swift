import Foundation

actor PlexDownloadJobRegistry {
    private struct Document: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let jobs: [PlexDownloadJob]
    }

    private let rootURL: URL
    private var cachedJobs: [UUID: PlexDownloadJob]?

    init(rootURL: URL = PlexDownloadPackageStore.defaultRootURL()) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func jobs() throws -> [PlexDownloadJob] {
        try loadIfNeeded().values.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func save(_ job: PlexDownloadJob) throws {
        var jobs = try loadIfNeeded()
        jobs[job.id] = job
        try persist(jobs)
        cachedJobs = jobs
    }

    func remove(withID id: UUID) throws {
        var jobs = try loadIfNeeded()
        guard jobs.removeValue(forKey: id) != nil else { return }
        try persist(jobs)
        cachedJobs = jobs
    }

    private func loadIfNeeded() throws -> [UUID: PlexDownloadJob] {
        if let cachedJobs { return cachedJobs }
        let url = registryURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            cachedJobs = [:]
            return [:]
        }
        let data = try Data(contentsOf: url)
        let document = try Self.decoder.decode(Document.self, from: data)
        guard document.schemaVersion == Document.currentSchemaVersion,
              Set(document.jobs.map(\.id)).count == document.jobs.count else {
            throw PlexDownloadTransferError.registryUnavailable
        }
        let jobs = Dictionary(uniqueKeysWithValues: document.jobs.map { ($0.id, $0) })
        cachedJobs = jobs
        return jobs
    }

    private func persist(_ jobs: [UUID: PlexDownloadJob]) throws {
        try FileManager.default.createDirectory(at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let document = Document(
            schemaVersion: Document.currentSchemaVersion,
            jobs: jobs.values.sorted { $0.id.uuidString < $1.id.uuidString }
        )
        try Self.encoder.encode(document).write(to: registryURL, options: .atomic)
    }

    private var registryURL: URL {
        rootURL
            .appendingPathComponent("Jobs", isDirectory: true)
            .appendingPathComponent("registry.json")
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

actor PlexOfflinePlaybackRegistry {
    private struct Document: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let records: [PlexOfflinePlaybackRecord]
    }

    private let rootURL: URL
    private var cachedRecords: [UUID: PlexOfflinePlaybackRecord]?

    init(rootURL: URL = PlexDownloadPackageStore.defaultRootURL()) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func records() throws -> [PlexOfflinePlaybackRecord] {
        Array(try loadIfNeeded().values)
    }

    func record(for packageID: UUID) throws -> PlexOfflinePlaybackRecord? {
        try loadIfNeeded()[packageID]
    }

    func save(_ record: PlexOfflinePlaybackRecord) throws {
        var records = try loadIfNeeded()
        records[record.id] = record
        try persist(records)
        cachedRecords = records
    }

    func remove(packageID: UUID) throws {
        var records = try loadIfNeeded()
        guard records.removeValue(forKey: packageID) != nil else { return }
        try persist(records)
        cachedRecords = records
    }

    private func loadIfNeeded() throws -> [UUID: PlexOfflinePlaybackRecord] {
        if let cachedRecords { return cachedRecords }
        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            cachedRecords = [:]
            return [:]
        }
        let document = try Self.decoder.decode(Document.self, from: Data(contentsOf: registryURL))
        guard document.schemaVersion == Document.currentSchemaVersion,
              Set(document.records.map(\.id)).count == document.records.count else {
            throw PlexDownloadTransferError.registryUnavailable
        }
        let records = Dictionary(uniqueKeysWithValues: document.records.map { ($0.id, $0) })
        cachedRecords = records
        return records
    }

    private func persist(_ records: [UUID: PlexOfflinePlaybackRecord]) throws {
        try FileManager.default.createDirectory(at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let document = Document(
            schemaVersion: Document.currentSchemaVersion,
            records: records.values.sorted { $0.id.uuidString < $1.id.uuidString }
        )
        try Self.encoder.encode(document).write(to: registryURL, options: .atomic)
    }

    private var registryURL: URL {
        rootURL
            .appendingPathComponent("Playback", isDirectory: true)
            .appendingPathComponent("offline-progress.json")
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
