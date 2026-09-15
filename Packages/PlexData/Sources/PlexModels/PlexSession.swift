import Foundation

public enum PlexSessionContentKind: String, Equatable, Sendable {
    case movie
    case tv
    case liveTV
    case track
    case photo
    case clip
    case other

    public init(type: String?, live: Bool) {
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

    public var displayName: String {
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

    public var contentMetaSymbolName: String {
        symbolName
    }

    public var contentMetaLabel: String {
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

    public var symbolName: String {
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

    public var streamArtworkLayout: PlexStreamArtworkLayout {
        switch self {
        case .track:
            .squareCover
        default:
            .poster
        }
    }
}

public enum PlexStreamArtworkLayout: Equatable, Sendable {
    case poster
    case squareCover

    public var aspectRatio: Double {
        switch self {
        case .poster:
            2.0 / 3.0
        case .squareCover:
            1.0
        }
    }
}

public struct PlexSession: Decodable, Identifiable, Sendable {
    public let sessionKey: String?
    public let ratingKey: String?
    public let key: String?
    public let type: String?
    public let subtype: String?
    public let live: Bool?
    public let title: String
    public let grandparentTitle: String?
    public let parentTitle: String?
    public let parentIndex: Int?
    public let index: Int?
    public let thumb: String?
    public let parentThumb: String?
    public let grandparentThumb: String?
    public let art: String?
    public let duration: Int?
    public let viewOffset: Int?
    public let year: Int?
    public let user: PlexUser?
    public let player: PlexPlayer
    public let session: PlexPlaybackSession?
    public let transcodeSession: PlexTranscodeSession?
    public let media: [PlexMedia]?

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

    public init(
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

    public init(from decoder: Decoder) throws {
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

    public var id: String {
        guard let canonicalSessionKey else {
            preconditionFailure("PlexSession requires a canonical session key for active stream identity.")
        }

        return canonicalSessionKey
    }

    public var canonicalSessionKey: String? {
        sessionKey?.nilIfBlank ?? session?.id?.nilIfBlank
    }

    public var transcodeSessionKey: String? {
        transcodeSession?.key?.nilIfBlank
    }

    public var serverSessionID: String? {
        session?.id?.nilIfBlank
    }

    public var posterPath: String? {
        preferredPosterCandidates
            .compactMap { $0?.nilIfBlank }
            .first
    }

    public var contentKind: PlexSessionContentKind {
        PlexSessionContentKind(type: type, live: isLive)
    }

    public var streamArtworkLayout: PlexStreamArtworkLayout {
        contentKind.streamArtworkLayout
    }

    public var isLive: Bool {
        live == true
    }

    public var headline: String {
        switch contentKind {
        case .tv, .liveTV:
            return grandparentTitle ?? title
        case .track:
            return title
        default:
            return title
        }
    }

    public var detailLine: String {
        switch contentKind {
        case .tv, .liveTV:
            return PlexEpisodeText.subtitle(season: parentIndex, episode: index, title: title)
        case .track:
            let pieces = [parentTitle, title].compactMap { $0?.nilIfBlank }
            return pieces.joined(separator: " • ")
        case .movie:
            return year.map(String.init) ?? "Movie"
        default:
            return parentTitle?.nilIfBlank ?? type?.capitalized ?? title
        }
    }

    public var contentSubtitle: String? {
        switch contentKind {
        case .tv, .liveTV:
            return title.nilIfBlank
        case .track:
            return nil
        default:
            return nil
        }
    }

    public var contentMetaLine: String? {
        switch contentKind {
        case .tv, .liveTV:
            return seasonEpisodeLine
        case .track:
            return grandparentTitle?.nilIfBlank
        case .movie:
            return year.map(String.init)
        default:
            return nil
        }
    }

    public var viewerLine: String {
        "\(userDisplayName) on \(playerDisplayName)"
    }

    public var playbackLine: String {
        [playbackStatusDisplayName, decisionDisplayName, locationDisplayName].compactMap { $0?.nilIfBlank }.joined(separator: " • ")
    }

    public var isPaused: Bool {
        player.state?.nilIfBlank?.lowercased() == "paused"
    }

    public var geoLookupIPAddress: String? {
        guard player.relayed != true else {
            return nil
        }

        return player.remotePublicAddress?.nilIfBlank
    }

    public func applying(playNotification: PlexPlaySessionStateNotification) -> PlexSession {
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

        if transcodeSession?.key == transcodeSessionKey {
            return transcodeSession
        }
        return PlexTranscodeSession(key: transcodeSessionKey)
    }

    public var progress: Double? {
        guard let duration, duration > 0, let viewOffset else {
            return nil
        }

        let rawProgress = Double(viewOffset) / Double(duration)
        return min(max(rawProgress, 0), 1)
    }

    public var audioStreamID: Int? {
        let audioStreams = media?
            .flatMap { $0.part ?? [] }
            .flatMap { $0.stream ?? [] }
            .filter(\.isAudio) ?? []

        return audioStreams.first(where: { $0.selected == true })?.id ?? audioStreams.first?.id
    }

    public func playbackTimingSummary(
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

    public var userDisplayName: String {
        user?.title?.nilIfBlank ?? "Unknown User"
    }

    public var playerDisplayName: String {
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

    private var seasonEpisodeLine: String? {
        PlexEpisodeText.numbers(season: parentIndex, episode: index)
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

public struct PlexUser: Decodable, Sendable {
    public let id: String?
    public let thumb: String?
    public let title: String?

    public init(
        id: String? = nil,
        thumb: String? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.thumb = thumb
        self.title = title
    }
}

public struct PlexPlayer: Decodable, Sendable {
    public let address: String?
    public let machineIdentifier: String?
    public let platform: String?
    public let product: String?
    public let remotePublicAddress: String?
    public let state: String?
    public let title: String?
    public let local: Bool?
    public let relayed: Bool?
    public let secure: Bool?

    public init(
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

    public func updating(state: String?) -> PlexPlayer {
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

public struct PlexPlaybackSession: Decodable, Sendable {
    public let id: String?
    public let bandwidth: Int?
    public let location: String?

    public init(
        id: String? = nil,
        bandwidth: Int? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.bandwidth = bandwidth
        self.location = location
    }
}

public struct PlexTranscodeSession: Decodable, Sendable {
    public let key: String?
    public let videoDecision: String?
    public let audioDecision: String?
    public let transcodeHwDecoding: String?
    public let transcodeHwEncoding: String?
    public let sourceVideoCodec: String?
    public let sourceAudioCodec: String?
    public let videoCodec: String?
    public let audioCodec: String?

    public init(key: String?, videoDecision: String? = nil, audioDecision: String? = nil,
         transcodeHwDecoding: String? = nil, transcodeHwEncoding: String? = nil,
         sourceVideoCodec: String? = nil, sourceAudioCodec: String? = nil,
         videoCodec: String? = nil, audioCodec: String? = nil) {
        self.key = key
        self.videoDecision = videoDecision
        self.audioDecision = audioDecision
        self.transcodeHwDecoding = transcodeHwDecoding
        self.transcodeHwEncoding = transcodeHwEncoding
        self.sourceVideoCodec = sourceVideoCodec
        self.sourceAudioCodec = sourceAudioCodec
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
    }
}

public struct PlexMedia: Decodable, Sendable {
    public let part: [PlexPart]?
    public let selected: Bool?

    public init(part: [PlexPart]?, selected: Bool? = nil) {
        self.part = part
        self.selected = selected
    }

    enum CodingKeys: String, CodingKey {
        case part = "Part"
        case selected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        part = try container.decodeIfPresent([PlexPart].self, forKey: .part)
        selected = try container.decodeFlexibleBoolIfPresent(forKey: .selected)
    }
}

public struct PlexPart: Decodable, Sendable {
    public let decision: String?
    public let stream: [PlexStream]?
    public let selected: Bool?

    public init(decision: String?, stream: [PlexStream]? = nil, selected: Bool? = nil) {
        self.decision = decision
        self.stream = stream
        self.selected = selected
    }

    enum CodingKeys: String, CodingKey {
        case decision
        case stream = "Stream"
        case selected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        decision = try container.decodeIfPresent(String.self, forKey: .decision)
        stream = try container.decodeIfPresent([PlexStream].self, forKey: .stream)
        selected = try container.decodeFlexibleBoolIfPresent(forKey: .selected)
    }
}

public struct PlexStream: Decodable, Sendable {
    public let id: Int?
    public let streamType: Int?
    public let codec: String?
    public let selected: Bool?
    public let decision: String?
    public let displayTitle: String?
    public let language: String?
    public let bitrate: Int?

    public var isAudio: Bool {
        streamType == 2
    }

    public init(id: Int?, streamType: Int?, codec: String? = nil, selected: Bool? = nil, decision: String? = nil, displayTitle: String? = nil, language: String? = nil, bitrate: Int? = nil) {
        self.id = id
        self.streamType = streamType
        self.codec = codec
        self.selected = selected
        self.decision = decision
        self.displayTitle = displayTitle
        self.language = language
        self.bitrate = bitrate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case streamType
        case codec
        case selected
        case decision
        case displayTitle
        case language
        case bitrate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleIntIfPresent(forKey: .id)
        streamType = try container.decodeFlexibleIntIfPresent(forKey: .streamType)
        codec = try container.decodeIfPresent(String.self, forKey: .codec)
        selected = try container.decodeFlexibleBoolIfPresent(forKey: .selected)
        decision = try container.decodeIfPresent(String.self, forKey: .decision)
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        bitrate = try container.decodeFlexibleIntIfPresent(forKey: .bitrate)
    }
}

public struct PlexStreamLevelsEnvelope: Decodable, Sendable {
    public let mediaContainer: PlexStreamLevelsContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    public init(
        mediaContainer: PlexStreamLevelsContainer
    ) {
        self.mediaContainer = mediaContainer
    }
}

public struct PlexStreamLevelsContainer: Decodable, Sendable {
    public let levels: [PlexStreamLevel]

    enum CodingKeys: String, CodingKey {
        case levels = "Level"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        levels = try container.decodeIfPresent([PlexStreamLevel].self, forKey: .levels) ?? []
    }
}

public struct PlexStreamLevel: Decodable, Sendable {
    public let value: Double?

    enum CodingKeys: String, CodingKey {
        case value = "v"
    }

    public init(
        value: Double? = nil
    ) {
        self.value = value
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }

        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

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
