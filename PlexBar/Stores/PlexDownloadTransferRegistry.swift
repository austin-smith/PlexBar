import Foundation

actor PlexDownloadTransferRegistry {
    private struct Document: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let records: [PlexDownloadTransferRecord]
    }

    private static let transfersDirectoryName = "Transfers"
    private static let registryFileName = "registry.json"

    private let rootURL: URL
    private var cachedRecords: [UUID: PlexDownloadTransferRecord]?

    init(rootURL: URL = PlexDownloadPackageStore.defaultRootURL()) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func records() throws -> [PlexDownloadTransferRecord] {
        let records = try loadIfNeeded()
        return records.values.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func record(withID id: UUID) throws -> PlexDownloadTransferRecord? {
        try loadIfNeeded()[id]
    }

    func save(_ record: PlexDownloadTransferRecord) throws {
        var records = try loadIfNeeded()
        records[record.id] = record
        try persist(records)
        cachedRecords = records
    }

    func remove(withID id: UUID) throws {
        var records = try loadIfNeeded()
        guard records.removeValue(forKey: id) != nil else {
            return
        }
        try persist(records)
        cachedRecords = records
    }

    private func loadIfNeeded() throws -> [UUID: PlexDownloadTransferRecord] {
        if let cachedRecords {
            return cachedRecords
        }
        let url = registryURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            cachedRecords = [:]
            return [:]
        }
        let data = try Data(contentsOf: url)
        let document = try Self.makeDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == Document.currentSchemaVersion,
              Set(document.records.map(\.id)).count == document.records.count else {
            throw PlexDownloadTransferError.registryUnavailable
        }
        let records = Dictionary(uniqueKeysWithValues: document.records.map { ($0.id, $0) })
        cachedRecords = records
        return records
    }

    private func persist(_ records: [UUID: PlexDownloadTransferRecord]) throws {
        let directoryURL = rootURL.appendingPathComponent(
            Self.transfersDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let sortedRecords = records.values.sorted { $0.id.uuidString < $1.id.uuidString }
        let document = Document(
            schemaVersion: Document.currentSchemaVersion,
            records: sortedRecords
        )
        let data = try Self.makeEncoder().encode(document)
        try data.write(to: registryURL(), options: .atomic)
    }

    private func registryURL() -> URL {
        rootURL
            .appendingPathComponent(Self.transfersDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.registryFileName)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
