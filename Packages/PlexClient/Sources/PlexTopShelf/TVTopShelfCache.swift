import CryptoKit
import Foundation

public struct TVTopShelfCache: Sendable {
    public static let appGroupIdentifier = "group.com.crapshack.PlexBar.tv"
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func shared() throws -> Self {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { throw CacheError.missingAppGroup }
        // tvOS may purge caches. Missing content deliberately returns the static Top Shelf image.
        return Self(directory: container.appending(path: "Library/Caches/TopShelf", directoryHint: .isDirectory))
    }

    private var manifestURL: URL { directory.appending(path: "content.json") }

    public func read() throws -> TVTopShelfSnapshot? {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        let snapshot = try JSONDecoder().decode(TVTopShelfSnapshot.self, from: Data(contentsOf: manifestURL))
        guard snapshot.version == TVTopShelfSnapshot.currentVersion else { throw CacheError.unsupportedVersion }
        return snapshot
    }

    public func imageURL(filename: String) -> URL? {
        // Only content-addressed local JPEGs may be passed to TVServices.
        guard filename.hasSuffix(".jpg"), filename.count == 68,
              filename.dropLast(4).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return directory.appending(path: filename)
    }

    @discardableResult
    public func storeImage(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".jpg"
        let url = directory.appending(path: filename)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        } else {
            // Retention starts at last publication, not the image's original download date.
            try FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path)
        }
        return filename
    }

    public func write(_ snapshot: TVTopShelfSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: manifestURL, options: .atomic)
    }

    public func clear() throws {
        // Invalidate the manifest first so a new extension request cannot load the previous session.
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try FileManager.default.removeItem(at: manifestURL)
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    public func pruneImages(keeping snapshot: TVTopShelfSnapshot, now: Date = .now) throws {
        let keep = Set(snapshot.sections.flatMap(\.items).map(\.imageFilename))
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )
        // Retain old artwork for one day: the Home Screen may still be displaying a previous snapshot.
        for file in files where file.pathExtension == "jpg" && !keep.contains(file.lastPathComponent) {
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values.contentModificationDate, now.timeIntervalSince(modified) > 86_400 {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    public enum CacheError: LocalizedError {
        case missingAppGroup
        case unsupportedVersion

        public var errorDescription: String? {
            switch self {
            case .missingAppGroup: "The Top Shelf shared app container is unavailable. Check App Groups signing."
            case .unsupportedVersion: "The Top Shelf cache format is unsupported. Open PlexBar to refresh it."
            }
        }
    }
}
