import Foundation

enum PlexSessionContentKind: String, Equatable {
    case movie
    case tv
    case liveTV
    case track
    case photo
    case clip
    case other

    init(type: String?, live: Bool) {
        if live {
            self = .liveTV
            return
        }

        switch type?.lowercased() {
        case "movie":
            self = .movie
        case "show", "season", "episode":
            self = .tv
        case "track":
            self = .track
        case "photo", "photoalbum":
            self = .photo
        case "clip":
            self = .clip
        default:
            self = .other
        }
    }

    var displayName: String {
        switch self {
        case .movie:
            "Movie"
        case .tv:
            "TV"
        case .liveTV:
            "Live TV"
        case .track:
            "Music"
        case .photo:
            "Photo"
        case .clip:
            "Clip"
        case .other:
            "Media"
        }
    }

    var contentMetaSymbolName: String {
        switch self {
        case .movie:
            "film"
        case .tv:
            "tv"
        case .liveTV:
            "antenna.radiowaves.left.and.right"
        case .track:
            "music.note"
        case .photo:
            "photo"
        case .clip:
            "play.rectangle"
        case .other:
            "play.square"
        }
    }

    var contentMetaLabel: String {
        switch self {
        case .movie:
            "Movie"
        case .tv:
            "TV"
        case .liveTV:
            "Live TV"
        case .track:
            "Music"
        case .photo:
            "Photo"
        case .clip:
            "Clip"
        case .other:
            "Media"
        }
    }

    var symbolName: String {
        switch self {
        case .movie:
            "film"
        case .tv:
            "tv"
        case .liveTV:
            "antenna.radiowaves.left.and.right"
        case .track:
            "music.note"
        case .photo:
            "photo"
        case .clip:
            "play.rectangle"
        case .other:
            "play.square"
        }
    }
}

struct PlexSession: Decodable, Identifiable {
    let ratingKey: String?
    let key: String?
    let type: String?
    let subtype: String?
    let live: Bool?
    let title: String
    let grandparentTitle: String?
    let parentTitle: String?
    let parentIndex: Int?
    let index: Int?
    let thumb: String?
    let parentThumb: String?
    let grandparentThumb: String?
    let art: String?
    let duration: Int?
    let viewOffset: Int?
    let year: Int?
    let user: PlexUser?
    let player: PlexPlayer
    let session: PlexPlaybackSession?
    let media: [PlexMedia]?

    enum CodingKeys: String, CodingKey {
        case ratingKey
        case key
        case type
        case subtype
        case live
        case title
        case grandparentTitle
        case parentTitle
        case parentIndex
        case index
        case thumb
        case parentThumb
        case grandparentThumb
        case art
        case duration
        case viewOffset
        case year
        case user = "User"
        case player = "Player"
        case session = "Session"
        case media = "Media"
    }

    init(
        ratingKey: String?,
        key: String?,
        type: String?,
        subtype: String?,
        live: Bool?,
        title: String,
        grandparentTitle: String?,
        parentTitle: String?,
        parentIndex: Int?,
        index: Int?,
        thumb: String?,
        parentThumb: String?,
        grandparentThumb: String?,
        art: String?,
        duration: Int?,
        viewOffset: Int?,
        year: Int?,
        user: PlexUser?,
        player: PlexPlayer,
        session: PlexPlaybackSession?,
        media: [PlexMedia]?
    ) {
        self.ratingKey = ratingKey
        self.key = key
        self.type = type
        self.subtype = subtype
        self.live = live
        self.title = title
        self.grandparentTitle = grandparentTitle
        self.parentTitle = parentTitle
        self.parentIndex = parentIndex
        self.index = index
        self.thumb = thumb
        self.parentThumb = parentThumb
        self.grandparentThumb = grandparentThumb
        self.art = art
        self.duration = duration
        self.viewOffset = viewOffset
        self.year = year
        self.user = user
        self.player = player
        self.session = session
        self.media = media
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        ratingKey = try container.decodeIfPresent(String.self, forKey: .ratingKey)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        subtype = try container.decodeIfPresent(String.self, forKey: .subtype)
        live = try container.decodeFlexibleBoolIfPresent(forKey: .live)
        title = try container.decode(String.self, forKey: .title)
        grandparentTitle = try container.decodeIfPresent(String.self, forKey: .grandparentTitle)
        parentTitle = try container.decodeIfPresent(String.self, forKey: .parentTitle)
        parentIndex = try container.decodeIfPresent(Int.self, forKey: .parentIndex)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
        parentThumb = try container.decodeIfPresent(String.self, forKey: .parentThumb)
        grandparentThumb = try container.decodeIfPresent(String.self, forKey: .grandparentThumb)
        art = try container.decodeIfPresent(String.self, forKey: .art)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        viewOffset = try container.decodeIfPresent(Int.self, forKey: .viewOffset)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        user = try container.decodeIfPresent(PlexUser.self, forKey: .user)
        player = try container.decode(PlexPlayer.self, forKey: .player)
        session = try container.decodeIfPresent(PlexPlaybackSession.self, forKey: .session)
        media = try container.decodeIfPresent([PlexMedia].self, forKey: .media)
    }

    var id: String {
        session?.id ?? ratingKey ?? key ?? [player.machineIdentifier, title].compactMap { $0 }.joined(separator: ":")
    }

    var posterPath: String? {
        preferredPosterCandidates
            .compactMap { $0?.nilIfBlank }
            .first
    }

    var contentKind: PlexSessionContentKind {
        PlexSessionContentKind(type: type, live: isLive)
    }

    var isLive: Bool {
        live == true
    }

    var headline: String {
        switch contentKind {
        case .tv, .liveTV, .track:
            return grandparentTitle ?? title
        default:
            return title
        }
    }

    var detailLine: String {
        switch contentKind {
        case .tv, .liveTV:
            let episodeLabel = episodeCode
            let pieces = [episodeLabel, title].compactMap { $0 }
            return pieces.joined(separator: " • ")
        case .track:
            let pieces = [parentTitle, title].compactMap { $0?.nilIfBlank }
            return pieces.joined(separator: " • ")
        case .movie:
            return year.map(String.init) ?? "Movie"
        default:
            return parentTitle?.nilIfBlank ?? type?.capitalized ?? title
        }
    }

    var contentSubtitle: String? {
        switch contentKind {
        case .tv, .liveTV:
            return title.nilIfBlank
        case .track:
            return title.nilIfBlank
        default:
            return nil
        }
    }

    var contentMetaLine: String? {
        switch contentKind {
        case .tv, .liveTV:
            return seasonEpisodeLine
        case .track:
            return parentTitle?.nilIfBlank
        case .movie:
            return year.map(String.init)
        default:
            return nil
        }
    }

    var viewerLine: String {
        "\(userDisplayName) on \(playerDisplayName)"
    }

    var playbackLine: String {
        [playbackStatusDisplayName, decisionDisplayName, locationDisplayName].compactMap { $0?.nilIfBlank }.joined(separator: " • ")
    }

    var isPaused: Bool {
        player.state?.nilIfBlank?.lowercased() == "paused"
    }

    var progress: Double? {
        guard let duration, duration > 0, let viewOffset else {
            return nil
        }

        let rawProgress = Double(viewOffset) / Double(duration)
        return min(max(rawProgress, 0), 1)
    }

    var userDisplayName: String {
        user?.title?.nilIfBlank ?? "Unknown User"
    }

    var playerDisplayName: String {
        player.title?.nilIfBlank ?? player.product?.nilIfBlank ?? "Unknown Player"
    }

    private var playbackStatusDisplayName: String? {
        guard let state = player.state?.nilIfBlank?.lowercased() else {
            return nil
        }

        switch state {
        case "playing", "paused":
            return nil
        default:
            return state.capitalized
        }
    }

    private var decisionDisplayName: String? {
        media?.first?.part?.first?.decision?.nilIfBlank?.capitalized
    }

    private var locationDisplayName: String? {
        session?.location?.nilIfBlank?.uppercased()
    }

    private var episodeCode: String? {
        let season = parentIndex.map { "S\($0)" }
        let episode = index.map { String(format: "E%02d", $0) }

        let code = [season, episode].compactMap { $0 }.joined()
        return code.isEmpty ? nil : code
    }

    private var seasonEpisodeLine: String? {
        let season = parentIndex.map { "S\($0)" }
        let episode = index.map { "E\($0)" }
        let pieces = [season, episode].compactMap { $0 }
        return pieces.isEmpty ? nil : pieces.joined(separator: " • ")
    }

    private var preferredPosterCandidates: [String?] {
        switch contentKind {
        case .tv, .liveTV:
            [grandparentThumb, parentThumb, thumb, art]
        case .track:
            [parentThumb, grandparentThumb, thumb, art]
        default:
            [thumb, parentThumb, grandparentThumb, art]
        }
    }
}

struct PlexUser: Decodable {
    let id: String?
    let thumb: String?
    let title: String?
}

struct PlexPlayer: Decodable {
    let address: String?
    let machineIdentifier: String?
    let platform: String?
    let product: String?
    let state: String?
    let title: String?
}

struct PlexPlaybackSession: Decodable {
    let id: String?
    let bandwidth: Int?
    let location: String?
}

struct PlexMedia: Decodable {
    let part: [PlexPart]?

    enum CodingKeys: String, CodingKey {
        case part = "Part"
    }
}

struct PlexPart: Decodable {
    let decision: String?
}

private extension KeyedDecodingContainer {
    func decodeFlexibleBoolIfPresent(forKey key: Key) throws -> Bool? {
        if let boolValue = try? decodeIfPresent(Bool.self, forKey: key) {
            return boolValue
        }

        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return intValue != 0
        }

        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }

        return nil
    }
}
