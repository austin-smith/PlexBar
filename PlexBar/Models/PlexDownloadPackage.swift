import PlexClientKit
import Foundation

struct PlexDownloadPackageIdentity: Codable, Equatable, Sendable {
    let packageID: UUID
    let accountID: Int?
    let serverIdentifier: String
    let queueID: Int
    let queueItemID: Int
    let metadataKey: String
    let ratingKey: String

    init(
        packageID: UUID = UUID(),
        accountID: Int,
        serverIdentifier: String,
        queueID: Int,
        queueItemID: Int,
        metadataKey: String,
        ratingKey: String
    ) {
        self.packageID = packageID
        self.accountID = accountID
        self.serverIdentifier = serverIdentifier
        self.queueID = queueID
        self.queueItemID = queueItemID
        self.metadataKey = metadataKey
        self.ratingKey = ratingKey
    }
}

struct PlexDownloadPackageManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let identity: PlexDownloadPackageIdentity
    let title: String
    let mediaType: String?
    let mediaFileName: String
    let mediaByteCount: Int64
    let contentType: String?
    let decisionFileName: String
    let artworkFileName: String?
    let completedAt: Date

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        identity: PlexDownloadPackageIdentity,
        title: String,
        mediaType: String?,
        mediaFileName: String,
        mediaByteCount: Int64,
        contentType: String?,
        decisionFileName: String,
        artworkFileName: String? = nil,
        completedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.title = title
        self.mediaType = mediaType
        self.mediaFileName = mediaFileName
        self.mediaByteCount = mediaByteCount
        self.contentType = contentType
        self.decisionFileName = decisionFileName
        self.artworkFileName = artworkFileName
        self.completedAt = completedAt
    }
}

struct PlexDownloadPackage: Identifiable, Equatable, Sendable {
    let manifest: PlexDownloadPackageManifest
    let packageURL: URL
    let mediaURL: URL
    let decisionURL: URL
    let artworkURL: URL?

    var id: UUID {
        manifest.identity.packageID
    }
}

struct PlexDownloadPackageIntegrityIssue: Error, Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case unreadableManifest
        case unsupportedSchemaVersion(Int)
        case packageIdentityMismatch
        case invalidManifest
        case missingDecision
        case missingMedia
        case mediaSizeMismatch(expected: Int64, actual: Int64)
    }

    let packageURL: URL
    let reason: Reason
}

struct PlexDownloadPackageReconciliation: Equatable, Sendable {
    let packages: [PlexDownloadPackage]
    let integrityIssues: [PlexDownloadPackageIntegrityIssue]
    let removedStagingPackageCount: Int
}

enum PlexDownloadPackageStoreError: LocalizedError, Equatable {
    case invalidIdentity
    case invalidTitle
    case invalidMediaFileExtension
    case invalidDecision
    case invalidDownloadedFile
    case missingEmbeddedSubtitle
    case invalidPackage

    var errorDescription: String? {
        switch self {
        case .invalidIdentity:
            "Plex did not provide a valid download identity."
        case .invalidTitle:
            "Plex did not provide a title for this download."
        case .invalidMediaFileExtension:
            "Plex provided an invalid downloaded-media file extension."
        case .invalidDecision:
            "Plex did not provide a valid download decision."
        case .invalidDownloadedFile:
            "The completed download is not a regular media file."
        case .missingEmbeddedSubtitle:
            "The completed download is missing the subtitle track Plex promised."
        case .invalidPackage:
            "The downloaded media package is incomplete or invalid."
        }
    }
}
