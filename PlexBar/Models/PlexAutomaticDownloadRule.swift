import PlexModels
import Foundation

enum PlexAutomaticDownloadPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case allEpisodes
    case unwatchedEpisodes

    var id: Self { self }

    var title: String {
        switch self {
        case .allEpisodes: "All Episodes"
        case .unwatchedEpisodes: "Unwatched Episodes"
        }
    }

    func includes(_ item: PlexMediaItem) -> Bool {
        guard item.type?.lowercased() == "episode" else { return false }
        return self == .allEpisodes || !item.isWatched
    }
}

struct PlexAutomaticDownloadRule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let accountID: Int
    let serverIdentifier: String
    let libraryID: String
    let sourceRatingKey: String
    let sourceChildrenPath: String
    let sourceType: String
    let title: String
    let posterPath: String?
    let policy: PlexAutomaticDownloadPolicy
    let keepsUpToDate: Bool
    let removesWatchedDownloads: Bool
    let createdAt: Date
    var lastRefreshedAt: Date?
    var lastErrorMessage: String?
}

actor PlexAutomaticDownloadRuleRegistry {
    private struct Document: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let rules: [PlexAutomaticDownloadRule]
    }

    private let rootURL: URL
    private var cachedRules: [UUID: PlexAutomaticDownloadRule]?

    init(rootURL: URL = PlexDownloadPackageStore.defaultRootURL()) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func rules() throws -> [PlexAutomaticDownloadRule] {
        try loadIfNeeded().values.sorted(by: Self.sort)
    }

    func save(_ rule: PlexAutomaticDownloadRule) throws {
        var rules = try loadIfNeeded()
        rules[rule.id] = rule
        try persist(rules)
        cachedRules = rules
    }

    func remove(withID id: UUID) throws {
        var rules = try loadIfNeeded()
        guard rules.removeValue(forKey: id) != nil else { return }
        try persist(rules)
        cachedRules = rules
    }

    private func loadIfNeeded() throws -> [UUID: PlexAutomaticDownloadRule] {
        if let cachedRules { return cachedRules }
        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            cachedRules = [:]
            return [:]
        }
        let document = try Self.decoder.decode(
            Document.self,
            from: Data(contentsOf: registryURL)
        )
        guard document.schemaVersion == Document.currentSchemaVersion,
              Set(document.rules.map(\.id)).count == document.rules.count else {
            throw PlexDownloadTransferError.registryUnavailable
        }
        let rules = Dictionary(uniqueKeysWithValues: document.rules.map { ($0.id, $0) })
        cachedRules = rules
        return rules
    }

    private func persist(_ rules: [UUID: PlexAutomaticDownloadRule]) throws {
        try FileManager.default.createDirectory(
            at: registryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let document = Document(
            schemaVersion: Document.currentSchemaVersion,
            rules: rules.values.sorted(by: Self.sort)
        )
        try Self.encoder.encode(document).write(to: registryURL, options: .atomic)
    }

    private var registryURL: URL {
        rootURL
            .appendingPathComponent("Rules", isDirectory: true)
            .appendingPathComponent("automatic-downloads.json")
    }

    private static func sort(
        _ lhs: PlexAutomaticDownloadRule,
        _ rhs: PlexAutomaticDownloadRule
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
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
