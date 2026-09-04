import Foundation

enum PlexDownloadJobState: String, Codable, Equatable, Sendable {
    case waitingForServer
    case transferring
    case paused
    case failed
}

struct PlexDownloadJob: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let accountID: Int
    let packageIdentity: PlexDownloadPackageIdentity
    let libraryID: String
    let title: String
    let mediaType: String?
    let source: PlexPlaybackSource
    let decisionParameters: PlexDownloadDecisionParameters
    let createdAt: Date
    var updatedAt: Date
    var state: PlexDownloadJobState
    var serverPreparationProgress: Double?
    var transferID: UUID?
    var errorMessage: String?
}

struct PlexOfflineMedia: Identifiable, Equatable, Sendable {
    let package: PlexDownloadPackage
    let item: PlexMediaItem

    var id: UUID { package.id }
}

struct PlexOfflinePlaybackRecord: Codable, Equatable, Identifiable, Sendable {
    let packageID: UUID
    let accountID: Int?
    let serverIdentifier: String
    let ratingKey: String
    var baselineViewOffset: Int?
    var baselineViewCount: Int?
    var position: Int
    var duration: Int
    var state: PlexTimelineState
    var updatedAt: Date
    var needsSync: Bool

    var id: UUID { packageID }
}

enum PlexDownloadWorkflowError: LocalizedError, Equatable {
    case unsupportedItem
    case missingLibrary
    case alreadyDownloaded
    case alreadyInProgress
    case invalidQueueResponse
    case serverPreparationFailed(String)
    case unavailableOfflineMedia
    case serverChanged
    case staleOfflineProgress
    case unsupportedAutomaticDownload
    case automaticDownloadAlreadyExists
    case invalidAutomaticDownloadHierarchy

    var errorDescription: String? {
        switch self {
        case .unsupportedItem:
            "This item does not contain media that Plex can download."
        case .missingLibrary:
            "Plex did not identify the library that owns this item."
        case .alreadyDownloaded:
            "This item is already downloaded."
        case .alreadyInProgress:
            "This item is already being downloaded."
        case .invalidQueueResponse:
            "Plex did not return the download queue item it created."
        case .serverPreparationFailed(let message):
            message
        case .unavailableOfflineMedia:
            "The downloaded media package is incomplete or no longer available."
        case .serverChanged:
            "Select the Plex server that owns this download to continue."
        case .staleOfflineProgress:
            "Plex has newer watch progress, so this offline progress was not uploaded."
        case .unsupportedAutomaticDownload:
            "Automatic downloads are available for shows and seasons."
        case .automaticDownloadAlreadyExists:
            "An automatic download already exists for this title."
        case .invalidAutomaticDownloadHierarchy:
            "Plex returned an invalid season or episode hierarchy for this title."
        }
    }
}
