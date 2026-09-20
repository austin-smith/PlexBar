import Foundation

struct PlexDownloadHandoffManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let transferID: UUID
    let statusCode: Int
    let contentType: String?
    let suggestedFileExtension: String?
    let completedAt: Date

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        transferID: UUID,
        statusCode: Int,
        contentType: String?,
        suggestedFileExtension: String?,
        completedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.transferID = transferID
        self.statusCode = statusCode
        self.contentType = contentType
        self.suggestedFileExtension = suggestedFileExtension
        self.completedAt = completedAt
    }
}

struct PlexDownloadHandoff: Equatable, Sendable {
    let manifest: PlexDownloadHandoffManifest
    let directoryURL: URL
    let mediaURL: URL
}

enum PlexDownloadHandoffError: Error, Equatable, Sendable {
    case invalidTransferIdentity
    case invalidResponse
    case serverStatus(Int)
    case invalidTemporaryFile
    case existingHandoffIsInvalid
    case publicationFailed
}
