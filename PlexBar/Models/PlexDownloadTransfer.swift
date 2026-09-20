import Foundation

enum PlexDownloadTransferState: String, Codable, Equatable, Sendable {
    case scheduled
    case transferring
    case paused
    case downloaded
    case publishing
    case failed
}

enum PlexDownloadTransferFailure: String, Codable, Equatable, Sendable {
    case invalidRequest
    case missingTask
    case invalidTaskIdentity
    case serverResponse
    case transfer
    case handoff
    case publication
}

struct PlexDownloadTransferRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let packageIdentity: PlexDownloadPackageIdentity
    let title: String
    let mediaType: String?
    let decisionData: Data
    let mediaFileExtension: String?
    let contentType: String?
    let taskIdentifier: Int
    let createdAt: Date
    var state: PlexDownloadTransferState
    var failure: PlexDownloadTransferFailure?

    init(
        id: UUID = UUID(),
        packageIdentity: PlexDownloadPackageIdentity,
        title: String,
        mediaType: String?,
        decisionData: Data,
        mediaFileExtension: String?,
        contentType: String?,
        taskIdentifier: Int,
        createdAt: Date = Date(),
        state: PlexDownloadTransferState = .scheduled,
        failure: PlexDownloadTransferFailure? = nil
    ) {
        self.id = id
        self.packageIdentity = packageIdentity
        self.title = title
        self.mediaType = mediaType
        self.decisionData = decisionData
        self.mediaFileExtension = mediaFileExtension
        self.contentType = contentType
        self.taskIdentifier = taskIdentifier
        self.createdAt = createdAt
        self.state = state
        self.failure = failure
    }
}

struct PlexDownloadTransferRequest: Sendable {
    let packageIdentity: PlexDownloadPackageIdentity
    let title: String
    let mediaType: String?
    let decisionData: Data
    let mediaFileExtension: String?
    let contentType: String?
    let request: URLRequest
}

struct PlexDownloadTransferTaskSnapshot: Equatable, Sendable {
    enum State: Int, Equatable, Sendable {
        case running
        case suspended
        case canceling
        case completed
    }

    let taskIdentifier: Int
    let taskDescription: String?
    let state: State
    let countOfBytesReceived: Int64
    let countOfBytesExpectedToReceive: Int64
}

struct PlexDownloadTransferProgress: Equatable, Sendable {
    let transferID: UUID
    let bytesReceived: Int64
    let bytesExpected: Int64?

    var fractionCompleted: Double? {
        guard let bytesExpected, bytesExpected > 0 else {
            return nil
        }
        return min(max(Double(bytesReceived) / Double(bytesExpected), 0), 1)
    }
}

enum PlexDownloadTransferEvent: Sendable {
    case progress(
        taskIdentifier: Int,
        taskDescription: String?,
        bytesReceived: Int64,
        bytesExpected: Int64
    )
    case handoffCompleted(
        taskIdentifier: Int,
        taskDescription: String?,
        result: Result<PlexDownloadHandoff, PlexDownloadHandoffError>
    )
    case taskCompleted(
        taskIdentifier: Int,
        taskDescription: String?,
        errorCode: Int?
    )
    case waitingForConnectivity(
        taskIdentifier: Int,
        taskDescription: String?
    )
}

enum PlexDownloadTransferError: LocalizedError {
    case invalidRequest
    case authorizationExpired
    case duplicateTransfer
    case taskCreationFailed
    case registryUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "PlexBar could not create a valid background download request."
        case .authorizationExpired:
            "The Plex download authorization expired before the transfer started."
        case .duplicateTransfer:
            "This Plex item already has an active download transfer."
        case .taskCreationFailed:
            "Foundation could not create the background download task."
        case .registryUnavailable:
            "PlexBar could not persist the download before starting it."
        }
    }
}
