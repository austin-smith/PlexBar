import Foundation
import ImageIO

actor PlexDownloadPreparedAssetStore {
    private let rootURL: URL

    init(rootURL: URL = PlexDownloadPackageStore.defaultRootURL()) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func saveArtwork(_ data: Data, packageID: UUID) throws {
        guard !data.isEmpty,
              CGImageSourceCreateWithData(data as CFData, nil) != nil else {
            return
        }
        let url = artworkURL(packageID: packageID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func artwork(packageID: UUID) throws -> Data? {
        let url = artworkURL(packageID: packageID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func remove(packageID: UUID) throws {
        let url = packageDirectoryURL(packageID: packageID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func packageDirectoryURL(packageID: UUID) -> URL {
        rootURL
            .appendingPathComponent("Prepared", isDirectory: true)
            .appendingPathComponent(packageID.uuidString, isDirectory: true)
    }

    private func artworkURL(packageID: UUID) -> URL {
        packageDirectoryURL(packageID: packageID).appendingPathComponent("artwork.jpg")
    }
}
