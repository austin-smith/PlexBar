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
        symbolName
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
        icon.symbolName
    }

    private var icon: PlexMediaIcon {
        switch self {
        case .movie:
            .movie
        case .tv:
            .show
        case .liveTV:
            .liveTV
        case .track:
            .music
        case .photo:
            .photo
        case .clip:
            .clip
        case .other:
            .other
        }
    }
}

struct PlexSession: Decodable, Identifiable {
    let sessionKey: String?
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
    let transcodeSession: PlexTranscodeSession?
    let media: [PlexMedia]?

    enum CodingKeys: String, CodingKey {
        case sessionKey
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
        case transcodeSession = "TranscodeSession"
        case media = "Media"
    }

    init(
        sessionKey: String? = nil,
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
        transcodeSession: PlexTranscodeSession? = nil,
        media: [PlexMedia]?
    ) {
        self.sessionKey = sessionKey
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
        self.transcodeSession = transcodeSession
        self.media = media
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        sessionKey = try container.decodeIfPresent(String.self, forKey: .sessionKey)
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
        transcodeSession = try container.decodeIfPresent(PlexTranscodeSession.self, forKey: .transcodeSession)
        media = try container.decodeIfPresent([PlexMedia].self, forKey: .media)
    }

    var id: String {
        guard let canonicalSessionKey else {
            preconditionFailure("PlexSession requires a canonical session key for active stream identity.")
        }

        return canonicalSessionKey
    }

    var canonicalSessionKey: String? {
        sessionKey?.nilIfBlank ?? session?.id?.nilIfBlank
    }

    var transcodeSessionKey: String? {
        transcodeSession?.key?.nilIfBlank
    }

    var serverSessionID: String? {
        session?.id?.nilIfBlank
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

    var geoLookupIPAddress: String? {
        guard player.relayed != true else {
            return nil
        }

        return player.remotePublicAddress?.nilIfBlank
    }

    func applying(playNotification: PlexPlaySessionStateNotification) -> PlexSession {
        PlexSession(
            sessionKey: playNotification.sessionKey ?? sessionKey,
            ratingKey: playNotification.hasRatingKey ? playNotification.ratingKey : ratingKey,
            key: playNotification.hasKey ? playNotification.key : key,
            type: type,
            subtype: subtype,
            live: live,
            title: title,
            grandparentTitle: grandparentTitle,
            parentTitle: parentTitle,
            parentIndex: parentIndex,
            index: index,
            thumb: thumb,
            parentThumb: parentThumb,
            grandparentThumb: grandparentThumb,
            art: art,
            duration: duration,
            viewOffset: playNotification.hasViewOffset ? playNotification.viewOffset : viewOffset,
            year: year,
            user: user,
            player: player.updating(state: playNotification.state),
            session: session,
            transcodeSession: updatedTranscodeSession(using: playNotification),
            media: media
        )
    }

    private func updatedTranscodeSession(using notification: PlexPlaySessionStateNotification) -> PlexTranscodeSession? {
        guard notification.hasTranscodeSession else {
            return transcodeSession
        }

        guard let transcodeSessionKey = notification.transcodeSessionKey?.nilIfBlank else {
            return nil
        }

        return PlexTranscodeSession(key: transcodeSessionKey)
    }

    var progress: Double? {
        guard let duration, duration > 0, let viewOffset else {
            return nil
        }

        let rawProgress = Double(viewOffset) / Double(duration)
        return min(max(rawProgress, 0), 1)
    }

    func playbackTimingSummary(
        referenceDate: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard let remainingMilliseconds else {
            return nil
        }

        let endDate = referenceDate.addingTimeInterval(Double(remainingMilliseconds) / 1000)
        let remainingTimeText = Self.remainingTimeText(milliseconds: remainingMilliseconds)

        guard !isPaused else {
            return remainingTimeText
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let endTime = formatter.string(from: endDate)

        return "\(remainingTimeText) (\(endTime))"
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

    private var remainingMilliseconds: Int? {
        guard !isLive,
              let duration,
              duration > 0,
              let viewOffset else {
            return nil
        }

        return max(duration - min(max(viewOffset, 0), duration), 0)
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

    private static func remainingTimeText(milliseconds: Int) -> String {
        let roundedMinutes = max(Int((Double(milliseconds) / 60000).rounded()), 1)

        guard roundedMinutes >= 60 else {
            return "\(roundedMinutes) min left"
        }

        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60
        let hourLabel = hours == 1 ? "1 hr" : "\(hours) hr"

        guard minutes > 0 else {
            return "\(hourLabel) left"
        }

        return "\(hourLabel) \(minutes) min left"
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
    let remotePublicAddress: String?
    let state: String?
    let title: String?
    let local: Bool?
    let relayed: Bool?
    let secure: Bool?

    init(
        address: String?,
        machineIdentifier: String?,
        platform: String?,
        product: String?,
        remotePublicAddress: String? = nil,
        state: String?,
        title: String?,
        local: Bool? = nil,
        relayed: Bool? = nil,
        secure: Bool? = nil
    ) {
        self.address = address
        self.machineIdentifier = machineIdentifier
        self.platform = platform
        self.product = product
        self.remotePublicAddress = remotePublicAddress
        self.state = state
        self.title = title
        self.local = local
        self.relayed = relayed
        self.secure = secure
    }

    func updating(state: String?) -> PlexPlayer {
        PlexPlayer(
            address: address,
            machineIdentifier: machineIdentifier,
            platform: platform,
            product: product,
            remotePublicAddress: remotePublicAddress,
            state: state ?? self.state,
            title: title,
            local: local,
            relayed: relayed,
            secure: secure
        )
    }
}

struct PlexPlaybackSession: Decodable {
    let id: String?
    let bandwidth: Int?
    let location: String?
}

struct PlexTranscodeSession: Decodable {
    let key: String?
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
