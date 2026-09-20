import PlexModels
import Foundation

public struct PlexHubEnvelope: Decodable, Sendable {
    public let mediaContainer: PlexHubContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    public init(mediaContainer: PlexHubContainer) {
        self.mediaContainer = mediaContainer
    }
}

public struct PlexHubContainer: Decodable, Sendable {
    public let hubs: [PlexHub]

    private enum CodingKeys: String, CodingKey {
        case hubs = "Hub"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hubs = try values.decodeIfPresent([PlexHub].self, forKey: .hubs) ?? []
    }
}

public struct PlexHub: Decodable, Equatable, Identifiable, Sendable {
    public let hubIdentifier: String
    public let hubKey: String?
    public let key: String?
    public let title: String
    public let type: String?
    public let style: String?
    public let size: Int?
    public let totalSize: Int?
    public let more: Bool
    public let promoted: Bool
    public var metadata: [PlexMediaItem]

    public var id: String {
        hubIdentifier
    }

    public var prefersPosterArtwork: Bool {
        switch hubIdentifier.lowercased() {
        case "continuewatching", "home.continue", "home.ondeck":
            true
        default:
            false
        }
    }

    public var isContinueWatching: Bool {
        hubIdentifier.caseInsensitiveCompare("continueWatching") == .orderedSame
            || hubIdentifier.caseInsensitiveCompare("home.continue") == .orderedSame
    }

    /// The dedicated feed owns continuation eligibility and item order. Never merge
    /// the legacy promoted rows into it, even when the unified feed is empty.
    public static func homeHubs(promoted: [PlexHub], continueWatching: [PlexHub]) throws -> [PlexHub] {
        guard continueWatching.count <= 1,
              continueWatching.allSatisfy({
                  $0.hubIdentifier.caseInsensitiveCompare("continueWatching") == .orderedSame
              }) else {
            throw PlexAPIError.invalidResponse
        }
        return continueWatching.filter { !$0.metadata.isEmpty }
            + promoted.filter {
                !$0.metadata.isEmpty && !$0.isContinueWatching
                    && $0.hubIdentifier.caseInsensitiveCompare("home.ondeck") != .orderedSame
            }
    }

    private enum CodingKeys: String, CodingKey {
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

    public init(from decoder: Decoder) throws {
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
