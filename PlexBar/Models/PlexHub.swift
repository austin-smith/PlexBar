import Foundation

struct PlexHubEnvelope: Decodable, Sendable {
    let mediaContainer: PlexHubContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexHubContainer: Decodable, Sendable {
    let hubs: [PlexHub]

    enum CodingKeys: String, CodingKey {
        case hubs = "Hub"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hubs = try values.decodeIfPresent([PlexHub].self, forKey: .hubs) ?? []
    }
}

struct PlexHub: Decodable, Equatable, Identifiable, Sendable {
    let hubIdentifier: String
    let hubKey: String?
    let key: String?
    let title: String
    let type: String?
    let style: String?
    let size: Int?
    let totalSize: Int?
    let more: Bool
    let promoted: Bool
    var metadata: [PlexMediaItem]

    var id: String {
        hubIdentifier
    }

    var prefersPosterArtwork: Bool {
        switch hubIdentifier.lowercased() {
        case "home.continue", "home.ondeck":
            true
        default:
            false
        }
    }

    var isContinueWatching: Bool {
        hubIdentifier.caseInsensitiveCompare("home.continue") == .orderedSame
    }

    enum CodingKeys: String, CodingKey {
        case hubIdentifier
        case hubKey
        case key
        case title
        case type
        case style
        case size
        case totalSize
        case more
        case promoted
        case metadata = "Metadata"
        case directories = "Directory"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hubIdentifier = try values.decode(String.self, forKey: .hubIdentifier)
        hubKey = try values.decodeIfPresent(String.self, forKey: .hubKey)
        key = try values.decodeIfPresent(String.self, forKey: .key)
        title = try values.decode(String.self, forKey: .title)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        style = try values.decodeIfPresent(String.self, forKey: .style)
        size = values.decodePlexIntIfPresent(forKey: .size)
        totalSize = values.decodePlexIntIfPresent(forKey: .totalSize)
        more = values.decodePlexBoolIfPresent(forKey: .more) ?? false
        promoted = values.decodePlexBoolIfPresent(forKey: .promoted) ?? false
        let metadataItems = try values.decodeIfPresent([PlexMediaItem].self, forKey: .metadata) ?? []
        let directoryItems = try values
            .decodeIfPresent([PlexHubDirectoryMediaItem].self, forKey: .directories)?
            .compactMap(\.mediaItem) ?? []
        metadata = metadataItems + directoryItems
    }
}

private struct PlexHubDirectoryMediaItem: Decodable {
    let mediaItem: PlexMediaItem?

    init(from decoder: Decoder) throws {
        mediaItem = try? PlexMediaItem(from: decoder)
    }
}
