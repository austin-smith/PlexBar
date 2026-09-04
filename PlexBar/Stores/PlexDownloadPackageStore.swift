import AVFoundation
import Foundation

actor PlexDownloadPackageStore {
    static let packageDirectoryExtension = "plexdownload"
    static let manifestFileName = "manifest.json"
    static let decisionFileName = "decision.json"
    static let artworkFileName = "artwork.jpg"

    private static let packagesDirectoryName = "Packages"
    private static let stagingPrefix = ".staging-"

    private let rootURL: URL
    private let fileManager: FileManager

    init(
        rootURL: URL = PlexDownloadPackageStore.defaultRootURL(),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.fileManager = fileManager
    }

    static func defaultRootURL() -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("PlexBar", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    func validateMetadata(
        identity: PlexDownloadPackageIdentity,
        title: String,
        decisionData: Data,
        mediaFileExtension: String?
    ) throws {
        try validate(identity: identity)
        guard title.nilIfBlank != nil else {
            throw PlexDownloadPackageStoreError.invalidTitle
        }
        guard Self.isValidDecisionDocument(decisionData, identity: identity) else {
            throw PlexDownloadPackageStoreError.invalidDecision
        }
        _ = try normalizedMediaFileExtension(mediaFileExtension)
    }

    func publish(
        identity: PlexDownloadPackageIdentity,
        title: String,
        mediaType: String?,
        decisionData: Data,
        downloadedFileURL: URL,
        mediaFileExtension: String?,
        contentType: String?,
        completedAt: Date = Date()
    ) async throws -> PlexDownloadPackage {
        try validateMetadata(
            identity: identity,
            title: title,
            decisionData: decisionData,
            mediaFileExtension: mediaFileExtension
        )
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateRegularFile(at: downloadedFileURL)

        let normalizedExtension = try normalizedMediaFileExtension(mediaFileExtension)
        let mediaFileName = normalizedExtension.map { "media.\($0)" } ?? "media"
        let packagesURL = try preparePackagesDirectory()
        let stagingURL = packagesURL.appendingPathComponent(
            Self.stagingPrefix + UUID().uuidString,
            isDirectory: true
        )
        let publishedURL = packageURL(for: identity.packageID, in: packagesURL)
        var shouldRemoveStaging = true

        try fileManager.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false
        )
        defer {
            if shouldRemoveStaging {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        let stagedMediaURL = stagingURL.appendingPathComponent(mediaFileName)
        try fileManager.moveItem(at: downloadedFileURL, to: stagedMediaURL)
        let mediaByteCount = try regularFileByteCount(at: stagedMediaURL)
        guard mediaByteCount > 0 else {
            throw PlexDownloadPackageStoreError.invalidDownloadedFile
        }
        try await validatePromisedEmbeddedSubtitle(
            decisionData: decisionData,
            mediaURL: stagedMediaURL
        )

        let decisionURL = stagingURL.appendingPathComponent(Self.decisionFileName)
        try decisionData.write(to: decisionURL, options: .atomic)

        let manifest = PlexDownloadPackageManifest(
            identity: identity,
            title: title,
            mediaType: mediaType?.nilIfBlank,
            mediaFileName: mediaFileName,
            mediaByteCount: mediaByteCount,
            contentType: contentType?.nilIfBlank,
            decisionFileName: Self.decisionFileName,
            completedAt: completedAt
        )
        let manifestData = try Self.makeManifestEncoder().encode(manifest)
        try manifestData.write(
            to: stagingURL.appendingPathComponent(Self.manifestFileName),
            options: .atomic
        )

        guard case .success = inspectPackage(
            at: stagingURL,
            expectedPackageID: identity.packageID
        ) else {
            throw PlexDownloadPackageStoreError.invalidPackage
        }

        if fileManager.fileExists(atPath: publishedURL.path) {
            _ = try fileManager.replaceItemAt(
                publishedURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(at: stagingURL, to: publishedURL)
        }
        shouldRemoveStaging = false

        guard case .success(let package) = inspectPackage(at: publishedURL) else {
            throw PlexDownloadPackageStoreError.invalidPackage
        }
        return package
    }

    func reconcile() throws -> PlexDownloadPackageReconciliation {
        let packagesURL = try preparePackagesDirectory()
        let childURLs = try fileManager.contentsOfDirectory(
            at: packagesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        )
        var removedStagingPackageCount = 0
        var packages: [PlexDownloadPackage] = []
        var integrityIssues: [PlexDownloadPackageIntegrityIssue] = []

        for childURL in childURLs {
            if childURL.lastPathComponent.hasPrefix(Self.stagingPrefix) {
                try fileManager.removeItem(at: childURL)
                removedStagingPackageCount += 1
                continue
            }
            guard childURL.pathExtension == Self.packageDirectoryExtension else {
                continue
            }

            switch inspectPackage(at: childURL) {
            case .success(let package):
                packages.append(package)
            case .failure(let issue):
                integrityIssues.append(issue)
            }
        }

        packages.sort {
            if $0.manifest.completedAt != $1.manifest.completedAt {
                return $0.manifest.completedAt > $1.manifest.completedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        integrityIssues.sort {
            $0.packageURL.lastPathComponent < $1.packageURL.lastPathComponent
        }

        return PlexDownloadPackageReconciliation(
            packages: packages,
            integrityIssues: integrityIssues,
            removedStagingPackageCount: removedStagingPackageCount
        )
    }

    func package(withID packageID: UUID) throws -> PlexDownloadPackage? {
        let packagesURL = try preparePackagesDirectory()
        let url = packageURL(for: packageID, in: packagesURL)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        guard case .success(let package) = inspectPackage(at: url) else {
            throw PlexDownloadPackageStoreError.invalidPackage
        }
        return package
    }

    func offlineMedia() throws -> [PlexOfflineMedia] {
        try reconcile().packages.map(offlineMedia(from:))
    }

    func offlineMedia(
        accountID: Int,
        serverIdentifier: String
    ) throws -> [PlexOfflineMedia] {
        guard accountID > 0,
              let serverIdentifier = serverIdentifier.nilIfBlank else {
            return []
        }
        return try offlineMedia().filter {
            $0.package.manifest.identity.accountID == accountID
                && $0.package.manifest.identity.serverIdentifier == serverIdentifier
        }
    }

    func offlineMedia(withID packageID: UUID) throws -> PlexOfflineMedia? {
        guard let package = try package(withID: packageID) else {
            return nil
        }
        return try offlineMedia(from: package)
    }

    func offlineMedia(
        withID packageID: UUID,
        accountID: Int,
        serverIdentifier: String
    ) throws -> PlexOfflineMedia? {
        guard accountID > 0,
              let serverIdentifier = serverIdentifier.nilIfBlank,
              let media = try offlineMedia(withID: packageID),
              media.package.manifest.identity.accountID == accountID,
              media.package.manifest.identity.serverIdentifier == serverIdentifier else {
            return nil
        }
        return media
    }

    func installArtwork(
        _ data: Data,
        for packageID: UUID
    ) throws -> PlexDownloadPackage {
        guard !data.isEmpty,
              let package = try package(withID: packageID) else {
            throw PlexDownloadPackageStoreError.invalidPackage
        }
        let artworkURL = package.packageURL.appendingPathComponent(Self.artworkFileName)
        try data.write(to: artworkURL, options: .atomic)

        let old = package.manifest
        let manifest = PlexDownloadPackageManifest(
            schemaVersion: old.schemaVersion,
            identity: old.identity,
            title: old.title,
            mediaType: old.mediaType,
            mediaFileName: old.mediaFileName,
            mediaByteCount: old.mediaByteCount,
            contentType: old.contentType,
            decisionFileName: old.decisionFileName,
            artworkFileName: Self.artworkFileName,
            completedAt: old.completedAt
        )
        try Self.makeManifestEncoder().encode(manifest).write(
            to: package.packageURL.appendingPathComponent(Self.manifestFileName),
            options: .atomic
        )
        guard case .success(let updated) = inspectPackage(at: package.packageURL) else {
            throw PlexDownloadPackageStoreError.invalidPackage
        }
        return updated
    }

    func removePackage(withID packageID: UUID) throws {
        let packagesURL = try preparePackagesDirectory()
        let url = packageURL(for: packageID, in: packagesURL)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func inspectPackage(
        at packageURL: URL,
        expectedPackageID: UUID? = nil
    ) -> Result<PlexDownloadPackage, PlexDownloadPackageIntegrityIssue> {
        let packageURL = packageURL.resolvingSymlinksInPath()
        let manifestURL = packageURL.appendingPathComponent(Self.manifestFileName)
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? Self.makeManifestDecoder().decode(
                  PlexDownloadPackageManifest.self,
                  from: manifestData
              ) else {
            return .failure(PlexDownloadPackageIntegrityIssue(
                packageURL: packageURL,
                reason: .unreadableManifest
            ))
        }
        guard manifest.schemaVersion == PlexDownloadPackageManifest.currentSchemaVersion else {
            return .failure(PlexDownloadPackageIntegrityIssue(
                packageURL: packageURL,
                reason: .unsupportedSchemaVersion(manifest.schemaVersion)
            ))
        }
        let packageID = expectedPackageID?.uuidString
            ?? packageURL.deletingPathExtension().lastPathComponent
        guard packageID == manifest.identity.packageID.uuidString else {
            return .failure(PlexDownloadPackageIntegrityIssue(
                packageURL: packageURL,
                reason: .packageIdentityMismatch
            ))
        }
        guard isValid(manifest: manifest) else {
            return .failure(PlexDownloadPackageIntegrityIssue(
                packageURL: packageURL,
                reason: .invalidManifest
            ))
        }

        let decisionURL = packageURL.appendingPathComponent(manifest.decisionFileName)
        guard isRegularFile(at: decisionURL),
              let decisionData = try? Data(contentsOf: decisionURL),
              Self.isValidDecisionDocument(
                  decisionData,
                  identity: manifest.identity
              ) else {
            return .failure(PlexDownloadPackageIntegrityIssue(
                packageURL: packageURL,
                reason: .missingDecision
            ))
        }

        let mediaURL = packageURL.appendingPathComponent(manifest.mediaFileName)
        guard let actualMediaByteCount = try? regularFileByteCount(at: mediaURL) else {
            return .failure(PlexDownloadPackageIntegrityIssue(
                packageURL: packageURL,
                reason: .missingMedia
            ))
        }
        guard actualMediaByteCount == manifest.mediaByteCount else {
            return .failure(PlexDownloadPackageIntegrityIssue(
                packageURL: packageURL,
                reason: .mediaSizeMismatch(
                    expected: manifest.mediaByteCount,
                    actual: actualMediaByteCount
                )
            ))
        }

        let artworkURL: URL?
        if let artworkFileName = manifest.artworkFileName {
            let candidate = packageURL.appendingPathComponent(artworkFileName)
            guard isRegularFile(at: candidate) else {
                return .failure(PlexDownloadPackageIntegrityIssue(
                    packageURL: packageURL,
                    reason: .invalidManifest
                ))
            }
            artworkURL = candidate
        } else {
            artworkURL = nil
        }

        return .success(PlexDownloadPackage(
            manifest: manifest,
            packageURL: packageURL,
            mediaURL: mediaURL,
            decisionURL: decisionURL,
            artworkURL: artworkURL
        ))
    }

    private func preparePackagesDirectory() throws -> URL {
        let packagesURL = rootURL.appendingPathComponent(
            Self.packagesDirectoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: packagesURL,
            withIntermediateDirectories: true
        )
        return packagesURL
    }

    private func validatePromisedEmbeddedSubtitle(
        decisionData: Data,
        mediaURL: URL
    ) async throws {
        guard Self.decisionPromisesEmbeddedSubtitle(decisionData) else { return }
        let asset = AVURLAsset(url: mediaURL)
        do {
            let group = try await asset.loadMediaSelectionGroup(for: .legible)
            guard group?.options.isEmpty == false else {
                throw PlexDownloadPackageStoreError.missingEmbeddedSubtitle
            }
        } catch let error as PlexDownloadPackageStoreError {
            throw error
        } catch {
            throw PlexDownloadPackageStoreError.missingEmbeddedSubtitle
        }
    }

    private func packageURL(for packageID: UUID, in packagesURL: URL) -> URL {
        packagesURL.appendingPathComponent(
            "\(packageID.uuidString).\(Self.packageDirectoryExtension)",
            isDirectory: true
        )
    }

    private func validate(identity: PlexDownloadPackageIdentity) throws {
        guard isValid(identity: identity) else {
            throw PlexDownloadPackageStoreError.invalidIdentity
        }
    }

    private func isValid(identity: PlexDownloadPackageIdentity) -> Bool {
        identity.accountID.map { $0 > 0 } == true
            && identity.serverIdentifier.nilIfBlank != nil
            && identity.queueID > 0
            && identity.queueItemID > 0
            && identity.ratingKey.nilIfBlank != nil
            && Self.isValidMetadataKey(identity.metadataKey)
    }

    private func normalizedMediaFileExtension(_ value: String?) throws -> String? {
        guard let value = value?.nilIfBlank else {
            return nil
        }
        let normalized = value.hasPrefix(".") ? String(value.dropFirst()) : value
        guard !normalized.isEmpty,
              normalized.count <= 12,
              normalized.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0)
              }) else {
            throw PlexDownloadPackageStoreError.invalidMediaFileExtension
        }
        return normalized.lowercased()
    }

    private func validateRegularFile(at url: URL) throws {
        guard isRegularFile(at: url) else {
            throw PlexDownloadPackageStoreError.invalidDownloadedFile
        }
    }

    private func isRegularFile(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func regularFileByteCount(at url: URL) throws -> Int64 {
        try validateRegularFile(at: url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize >= 0 else {
            throw PlexDownloadPackageStoreError.invalidDownloadedFile
        }
        return Int64(fileSize)
    }

    private func isValid(manifest: PlexDownloadPackageManifest) -> Bool {
        manifest.title.nilIfBlank != nil
            && manifest.mediaByteCount > 0
            && Self.isSafeFileName(manifest.mediaFileName)
            && manifest.artworkFileName.map(Self.isSafeFileName) != false
            && manifest.decisionFileName == Self.decisionFileName
            && isValid(identity: manifest.identity)
    }

    private func offlineMedia(from package: PlexDownloadPackage) throws -> PlexOfflineMedia {
        let data = try Data(contentsOf: package.decisionURL)
        let decision = try JSONDecoder()
            .decode(PlexDownloadQueueDecisionEnvelope.self, from: data)
            .mediaContainer
        guard let item = decision.metadata.first(where: {
            $0.ratingKey == package.manifest.identity.ratingKey
                && $0.key == package.manifest.identity.metadataKey
        }) else {
            throw PlexDownloadPackageStoreError.invalidDecision
        }
        return PlexOfflineMedia(package: package, item: item)
    }

    private static func isSafeFileName(_ value: String) -> Bool {
        value.nilIfBlank != nil
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains(":")
    }

    private static func isValidMetadataKey(_ key: String) -> Bool {
        guard let key = key.nilIfBlank,
              key.hasPrefix("/library/metadata/"),
              let components = URLComponents(string: key),
              components.scheme == nil,
              components.host == nil,
              components.query == nil,
              components.fragment == nil else {
            return false
        }
        let pathComponents = components.path.split(separator: "/", omittingEmptySubsequences: true)
        return pathComponents.count >= 3
            && pathComponents[0] == "library"
            && pathComponents[1] == "metadata"
            && pathComponents.dropFirst(2).allSatisfy { $0 != "." && $0 != ".." }
    }

    private static func isValidDecisionDocument(
        _ data: Data,
        identity: PlexDownloadPackageIdentity
    ) -> Bool {
        guard !data.isEmpty,
              let envelope = try? JSONDecoder().decode(
                  PlexDownloadQueueDecisionEnvelope.self,
                  from: data
              ) else {
            return false
        }
        return envelope.mediaContainer.metadata.contains {
            $0.key == identity.metadataKey && $0.ratingKey == identity.ratingKey
        }
    }

    private static func decisionPromisesEmbeddedSubtitle(_ data: Data) -> Bool {
        guard let decision = try? JSONDecoder()
            .decode(PlexDownloadQueueDecisionEnvelope.self, from: data)
            .mediaContainer else {
            return false
        }
        return decision.metadata
            .flatMap(\.media)
            .flatMap(\.parts)
            .flatMap(\.streams)
            .contains { stream in
                stream.streamType == 3
                    && stream.selected == true
                    && stream.decision?.lowercased() == "transcode"
            }
    }

    private static func makeManifestEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeManifestDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
