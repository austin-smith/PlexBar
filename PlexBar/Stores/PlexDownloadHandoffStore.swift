import Foundation

final class PlexDownloadHandoffStore: @unchecked Sendable {
    static let handoffDirectoryExtension = "plexhandoff"
    static let manifestFileName = "handoff.json"
    static let mediaFileName = "media"

    private static let incomingDirectoryName = "Incoming"
    private static let stagingPrefix = ".staging-"

    private let rootURL: URL
    private let lock = NSLock()

    init(rootURL: URL = PlexDownloadPackageStore.defaultRootURL()) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func accept(
        temporaryFileURL: URL,
        transferID: UUID,
        response: URLResponse?
    ) -> Result<PlexDownloadHandoff, PlexDownloadHandoffError> {
        lock.lock()
        defer { lock.unlock() }

        do {
            return .success(try acceptLocked(
                temporaryFileURL: temporaryFileURL,
                transferID: transferID,
                response: response
            ))
        } catch let error as PlexDownloadHandoffError {
            return .failure(error)
        } catch {
            return .failure(.publicationFailed)
        }
    }

    func handoff(for transferID: UUID) -> Result<PlexDownloadHandoff?, PlexDownloadHandoffError> {
        lock.lock()
        defer { lock.unlock() }

        do {
            let incomingURL = try prepareIncomingDirectory()
            let url = handoffURL(for: transferID, in: incomingURL)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .success(nil)
            }
            return .success(try inspectHandoff(at: url, expectedTransferID: transferID))
        } catch let error as PlexDownloadHandoffError {
            return .failure(error)
        } catch {
            return .failure(.publicationFailed)
        }
    }

    func removeHandoff(for transferID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        let incomingURL = try prepareIncomingDirectory()
        let url = handoffURL(for: transferID, in: incomingURL)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    func reconcile(validTransferIDs: Set<UUID>) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        let incomingURL = try prepareIncomingDirectory()
        let children = try fileManager.contentsOfDirectory(
            at: incomingURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        )
        var removedCount = 0

        for child in children {
            if child.lastPathComponent.hasPrefix(Self.stagingPrefix) {
                try fileManager.removeItem(at: child)
                removedCount += 1
                continue
            }
            guard child.pathExtension == Self.handoffDirectoryExtension else {
                continue
            }
            let transferID = UUID(
                uuidString: child.deletingPathExtension().lastPathComponent
            )
            guard transferID.map({ !validTransferIDs.contains($0) }) ?? true else {
                continue
            }
            try fileManager.removeItem(at: child)
            removedCount += 1
        }
        return removedCount
    }

    private func acceptLocked(
        temporaryFileURL: URL,
        transferID: UUID,
        response: URLResponse?
    ) throws -> PlexDownloadHandoff {
        guard let response = response as? HTTPURLResponse else {
            throw PlexDownloadHandoffError.invalidResponse
        }
        guard (200...299).contains(response.statusCode) else {
            throw PlexDownloadHandoffError.serverStatus(response.statusCode)
        }
        guard Self.isRegularNonSymbolicFile(at: temporaryFileURL) else {
            throw PlexDownloadHandoffError.invalidTemporaryFile
        }

        let fileManager = FileManager.default
        let incomingURL = try prepareIncomingDirectory()
        let finalURL = handoffURL(for: transferID, in: incomingURL)
        if fileManager.fileExists(atPath: finalURL.path) {
            do {
                return try inspectHandoff(
                    at: finalURL,
                    expectedTransferID: transferID
                )
            } catch {
                throw PlexDownloadHandoffError.existingHandoffIsInvalid
            }
        }

        let stagingURL = incomingURL.appendingPathComponent(
            Self.stagingPrefix + UUID().uuidString,
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        var shouldRemoveStaging = true
        defer {
            if shouldRemoveStaging {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        let mediaURL = stagingURL.appendingPathComponent(Self.mediaFileName)
        try fileManager.moveItem(at: temporaryFileURL, to: mediaURL)
        let suggestedExtension = response.suggestedFilename?
            .nilIfBlank
            .map { URL(fileURLWithPath: $0).pathExtension.nilIfBlank }
            ?? nil
        let manifest = PlexDownloadHandoffManifest(
            transferID: transferID,
            statusCode: response.statusCode,
            contentType: response.mimeType?.nilIfBlank,
            suggestedFileExtension: suggestedExtension
        )
        let manifestData = try Self.makeEncoder().encode(manifest)
        try manifestData.write(
            to: stagingURL.appendingPathComponent(Self.manifestFileName),
            options: .atomic
        )
        _ = try inspectHandoff(at: stagingURL, expectedTransferID: transferID)
        try fileManager.moveItem(at: stagingURL, to: finalURL)
        shouldRemoveStaging = false
        return try inspectHandoff(at: finalURL, expectedTransferID: transferID)
    }

    private func inspectHandoff(
        at directoryURL: URL,
        expectedTransferID: UUID
    ) throws -> PlexDownloadHandoff {
        guard Self.isDirectoryNonSymbolic(at: directoryURL) else {
            throw PlexDownloadHandoffError.existingHandoffIsInvalid
        }
        let directoryURL = directoryURL.resolvingSymlinksInPath()
        let manifestURL = directoryURL.appendingPathComponent(Self.manifestFileName)
        guard Self.isRegularNonSymbolicFile(at: manifestURL),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? Self.makeDecoder().decode(
                  PlexDownloadHandoffManifest.self,
                  from: data
              ),
              manifest.schemaVersion == PlexDownloadHandoffManifest.currentSchemaVersion,
              manifest.transferID == expectedTransferID,
              (200...299).contains(manifest.statusCode) else {
            throw PlexDownloadHandoffError.existingHandoffIsInvalid
        }
        let mediaURL = directoryURL.appendingPathComponent(Self.mediaFileName)
        guard Self.isRegularNonSymbolicFile(at: mediaURL) else {
            throw PlexDownloadHandoffError.existingHandoffIsInvalid
        }
        return PlexDownloadHandoff(
            manifest: manifest,
            directoryURL: directoryURL,
            mediaURL: mediaURL
        )
    }

    private func prepareIncomingDirectory() throws -> URL {
        let url = rootURL.appendingPathComponent(
            Self.incomingDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func handoffURL(for transferID: UUID, in incomingURL: URL) -> URL {
        incomingURL.appendingPathComponent(
            "\(transferID.uuidString).\(Self.handoffDirectoryExtension)",
            isDirectory: true
        )
    }

    private static func isRegularNonSymbolicFile(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func isDirectoryNonSymbolic(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
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
