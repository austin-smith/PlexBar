import Foundation

enum PlexDownloadQueueStatus: String, Decodable, Equatable, Sendable {
    case deciding
    case waiting
    case processing
    case done
    case error
}

struct PlexDownloadQueue: Decodable, Equatable, Sendable {
    let id: Int
    let status: PlexDownloadQueueStatus
    let itemCount: Int
}

enum PlexDownloadQueueItemStatus: String, Decodable, Equatable, Sendable {
    case deciding
    case waiting
    case processing
    case available
    case error
    case expired
}

struct PlexDownloadDecisionResult: Decodable, Equatable, Sendable {
    let mdeDecisionCode: Int?
    let mdeDecisionText: String?
    let availableBandwidth: Int?
    let generalDecisionCode: Int?
    let generalDecisionText: String?
    let directPlayDecisionCode: Int?
    let directPlayDecisionText: String?
    let transcodeDecisionCode: Int?
    let transcodeDecisionText: String?
}

struct PlexDownloadTranscodeSession: Decodable, Equatable, Sendable {
    let key: String?
    let throttled: Bool?
    let complete: Bool?
    let progress: Double?
    let size: Int64?
    let speed: Double?
    let error: Bool?
    let duration: Int64?
    let context: String?
    let sourceVideoCodec: String?
    let sourceAudioCodec: String?
    let `protocol`: String?
    let transcodeHwRequested: Bool?
    let transcodeHwFullPipeline: Bool?
}

struct PlexDownloadQueueItem: Decodable, Equatable, Identifiable, Sendable {
    let id: Int
    let queueID: Int
    let key: String
    let status: PlexDownloadQueueItemStatus
    let error: String?
    let decisionResult: PlexDownloadDecisionResult?
    let transcodeSession: PlexDownloadTranscodeSession?

    enum CodingKeys: String, CodingKey {
        case id
        case queueID = "queueId"
        case key
        case status
        case error
        case decisionResult = "DecisionResult"
        case transcodeSession = "TranscodeSession"
    }

    var failureDescription: String? {
        let decisionMessages = [
            decisionResult?.generalDecisionText,
            decisionResult?.mdeDecisionText,
            decisionResult?.directPlayDecisionText,
            decisionResult?.transcodeDecisionText,
        ]
            .compactMap { $0?.nilIfBlank }
            .reduce(into: [String]()) { messages, message in
                if !messages.contains(message) {
                    messages.append(message)
                }
            }

        if !decisionMessages.isEmpty {
            return decisionMessages.joined(separator: " ")
        }
        return error?.nilIfBlank
    }
}

struct PlexAddedDownloadQueueItem: Decodable, Equatable, Sendable {
    let key: String
    let id: Int
}

enum PlexDownloadProtocol: String, Codable, Equatable, Sendable {
    case http
    case hls
    case dash
}

enum PlexDownloadSubtitleMode: String, Codable, Equatable, Sendable {
    case automatic = "auto"
    case burn
    case none
    case sidecar
    case embedded
    case segmented
    case unknown
}

enum PlexDownloadAdvancedSubtitleMode: String, Codable, Equatable, Sendable {
    case burn
    case text
    case unknown
}

struct PlexDownloadDecisionParameters: Codable, Equatable, Sendable {
    let mediaPath: String?
    let mediaIndex: Int?
    let partIndex: Int?
    let deliveryProtocol: PlexDownloadProtocol?
    let allowsDirectPlay: Bool?
    let allowsDirectStream: Bool?
    let allowsDirectStreamAudio: Bool?
    let subtitleMode: PlexDownloadSubtitleMode?
    let advancedSubtitleMode: PlexDownloadAdvancedSubtitleMode?
    let videoBitrate: Int?
    let videoQuality: Int?
    let videoResolution: String?
    let musicBitrate: Int?
    let sessionIdentifier: String?
    let clientProfileName: String?
    let clientProfileExtra: String?

    init(
        mediaPath: String? = nil,
        mediaIndex: Int? = nil,
        partIndex: Int? = nil,
        deliveryProtocol: PlexDownloadProtocol? = nil,
        allowsDirectPlay: Bool? = nil,
        allowsDirectStream: Bool? = nil,
        allowsDirectStreamAudio: Bool? = nil,
        subtitleMode: PlexDownloadSubtitleMode? = nil,
        advancedSubtitleMode: PlexDownloadAdvancedSubtitleMode? = nil,
        videoBitrate: Int? = nil,
        videoQuality: Int? = nil,
        videoResolution: String? = nil,
        musicBitrate: Int? = nil,
        sessionIdentifier: String? = nil,
        clientProfileName: String? = nil,
        clientProfileExtra: String? = nil
    ) {
        self.mediaPath = mediaPath
        self.mediaIndex = mediaIndex
        self.partIndex = partIndex
        self.deliveryProtocol = deliveryProtocol
        self.allowsDirectPlay = allowsDirectPlay
        self.allowsDirectStream = allowsDirectStream
        self.allowsDirectStreamAudio = allowsDirectStreamAudio
        self.subtitleMode = subtitleMode
        self.advancedSubtitleMode = advancedSubtitleMode
        self.videoBitrate = videoBitrate
        self.videoQuality = videoQuality
        self.videoResolution = videoResolution
        self.musicBitrate = musicBitrate
        self.sessionIdentifier = sessionIdentifier
        self.clientProfileName = clientProfileName
        self.clientProfileExtra = clientProfileExtra
    }
}

struct PlexDownloadQueueDecision: Decodable, Sendable {
    let allowSync: Bool?
    let generalDecisionCode: Int?
    let generalDecisionText: String?
    let directPlayDecisionCode: Int?
    let directPlayDecisionText: String?
    let transcodeDecisionCode: Int?
    let transcodeDecisionText: String?
    let resourceSession: String?
    let metadata: [PlexMediaItem]

    enum CodingKeys: String, CodingKey {
        case allowSync
        case generalDecisionCode
        case generalDecisionText
        case directPlayDecisionCode
        case directPlayDecisionText
        case transcodeDecisionCode
        case transcodeDecisionText
        case resourceSession
        case metadata = "Metadata"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        allowSync = values.decodePlexBoolIfPresent(forKey: .allowSync)
        generalDecisionCode = values.decodePlexIntIfPresent(forKey: .generalDecisionCode)
        generalDecisionText = try values.decodeIfPresent(String.self, forKey: .generalDecisionText)
        directPlayDecisionCode = values.decodePlexIntIfPresent(forKey: .directPlayDecisionCode)
        directPlayDecisionText = try values.decodeIfPresent(String.self, forKey: .directPlayDecisionText)
        transcodeDecisionCode = values.decodePlexIntIfPresent(forKey: .transcodeDecisionCode)
        transcodeDecisionText = try values.decodeIfPresent(String.self, forKey: .transcodeDecisionText)
        resourceSession = try values.decodeIfPresent(String.self, forKey: .resourceSession)
        metadata = try values.decodeIfPresent([PlexMediaItem].self, forKey: .metadata) ?? []
    }
}

struct PlexDownloadQueueEnvelope: Decodable {
    let mediaContainer: Container

    struct Container: Decodable {
        let queues: [PlexDownloadQueue]

        enum CodingKeys: String, CodingKey {
            case queues = "DownloadQueue"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            queues = try values.decodeIfPresent([PlexDownloadQueue].self, forKey: .queues) ?? []
        }
    }

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexDownloadQueueItemsEnvelope: Decodable {
    let mediaContainer: Container

    struct Container: Decodable {
        let items: [PlexDownloadQueueItem]

        enum CodingKeys: String, CodingKey {
            case items = "DownloadQueueItem"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            items = try values.decodeIfPresent([PlexDownloadQueueItem].self, forKey: .items) ?? []
        }
    }

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexAddedDownloadQueueItemsEnvelope: Decodable {
    let mediaContainer: Container

    struct Container: Decodable {
        let items: [PlexAddedDownloadQueueItem]

        enum CodingKeys: String, CodingKey {
            case items = "AddedQueueItems"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            items = try values.decodeIfPresent([PlexAddedDownloadQueueItem].self, forKey: .items) ?? []
        }
    }

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexDownloadQueueDecisionEnvelope: Decodable {
    let mediaContainer: PlexDownloadQueueDecision

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexDownloadQueueDecisionDocument: Sendable {
    let decision: PlexDownloadQueueDecision
    let data: Data
}
