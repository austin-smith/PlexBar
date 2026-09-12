import Foundation

struct PlexMediaItem: Decodable, Equatable, Hashable, Identifiable, Sendable {
    let ratingKey: String
    let key: String?
    let guid: String?
    let type: String?
    let subtype: String?
    let title: String
    let originalTitle: String?
    let reason: String?
    let reasonTitle: String?
    let reasonID: String?
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let librarySectionID: String?
    let librarySectionTitle: String?
    let parentTitle: String?
    let grandparentTitle: String?
    let year: Int?
    let index: Int?
    let parentIndex: Int?
    let duration: Int?
    let summary: String?
    let tagline: String?
    let thumb: String?
    let composite: String?
    let parentThumb: String?
    let grandparentThumb: String?
    let art: String?
    let images: [PlexMediaImage]
    let studio: String?
    let contentRating: String?
    let originallyAvailableAt: String?
    let rating: Double?
    let ratingImage: String?
    let audienceRating: Double?
    let audienceRatingImage: String?
    let guids: [PlexMediaGUID]
    let ratings: [PlexMediaRating]
    var userRating: Double?
    var viewOffset: Int?
    var viewCount: Int?
    let leafCount: Int?
    var viewedLeafCount: Int?
    let childCount: Int?
    let skipChildren: Bool?
    let skipParent: Bool?
    let primaryExtraKey: String?
    let playQueueItemID: String?
    let playlistItemID: String?
    let playlistType: String?
    let smart: Bool?
    let readOnly: Bool?
    let media: [PlexMediaVersion]
    let genres: [PlexTag]
    let directors: [PlexTag]
    let writers: [PlexTag]
    let producers: [PlexTag]
    let countries: [PlexTag]
    let roles: [PlexTag]
    let chapters: [PlexMediaChapter]
    let markers: [PlexMediaMarker]

    var id: String {
        playQueueItemID.map { "play-queue-item:\($0)" }
            ?? playlistItemID.map { "playlist-item:\($0)" }
            ?? ratingKey
    }

    var isPlayable: Bool {
        supportsNativePlayback && media.contains { !$0.parts.isEmpty }
    }

    var supportsNativePlayback: Bool {
        type?.lowercased() != "photo"
    }

    var hasChildren: Bool {
        guard let type = type?.lowercased() else {
            return false
        }

        return [
            "show", "season", "artist", "album", "photoalbum", "collection", "playlist",
            "playlistfolder"
        ].contains(type)
    }

    var childrenPath: String? {
        guard hasChildren, let key else {
            return nil
        }

        guard skipChildren == true,
              var components = URLComponents(string: key),
              components.path.hasSuffix("/children") else {
            return key
        }

        components.path = String(components.path.dropLast("children".count)) + "grandchildren"
        return components.string
    }

    func hierarchyRequestItem(afterRefreshingWith details: PlexMediaItem) -> PlexMediaItem {
        guard ratingKey == details.ratingKey,
              childrenPath == nil,
              details.childrenPath != nil else {
            return self
        }
        return details
    }

    var progress: Double? {
        guard let duration, duration > 0, let viewOffset else {
            return nil
        }

        return min(max(Double(viewOffset) / Double(duration), 0), 1)
    }

    var isWatched: Bool {
        if let leafCount, leafCount > 0, let viewedLeafCount {
            return viewedLeafCount >= leafCount
        }
        return (viewCount ?? 0) > 0
    }

    var supportsWatchedStateMutation: Bool {
        guard let type = type?.lowercased() else {
            return false
        }
        return ["movie", "show", "season", "episode"].contains(type)
    }

    var supportsPlaybackHistory: Bool {
        guard Int(ratingKey) != nil, let type = type?.lowercased() else {
            return false
        }

        return ["movie", "show", "season", "episode", "artist", "album", "track"].contains(type)
    }

    func mergingWatchedState(from refreshedItem: PlexMediaItem) -> PlexMediaItem {
        guard ratingKey == refreshedItem.ratingKey else {
            return self
        }

        var merged = self
        merged.viewOffset = refreshedItem.viewOffset
        merged.viewCount = refreshedItem.viewCount
        merged.viewedLeafCount = refreshedItem.viewedLeafCount
        return merged
    }

    func mergingUserRating(from refreshedItem: PlexMediaItem) -> PlexMediaItem {
        guard ratingKey == refreshedItem.ratingKey else {
            return self
        }

        var merged = self
        merged.userRating = refreshedItem.userRating
        return merged
    }

    var supportsMetadataRefresh: Bool {
        guard let type = type?.lowercased() else {
            return false
        }
        return [
            "movie", "show", "season", "episode", "artist", "album", "track", "photo", "photoalbum"
        ].contains(type)
    }

    var preferredArtworkPath: String? {
        thumb?.nilIfBlank ?? composite?.nilIfBlank
    }

    var formattedDuration: String? {
        guard let duration, duration > 0 else {
            return nil
        }

        let roundedMinutes = max((Int64(duration) + 30_000) / 60_000, 1)
        return Duration.seconds(roundedMinutes * 60)
            .formatted(.units(width: .abbreviated))
            .replacingOccurrences(of: ", ", with: " ")
    }

    var posterArtworkPath: String? {
        switch type?.lowercased() {
        case "episode":
            grandparentThumb?.nilIfBlank
                ?? parentThumb?.nilIfBlank
        case "season":
            grandparentThumb?.nilIfBlank
                ?? parentThumb?.nilIfBlank
                ?? preferredArtworkPath
        default:
            preferredArtworkPath
        }
    }

    var nowPlayingArtworkPaths: [String] {
        let candidates: [String?] = switch type?.lowercased() {
        case "episode":
            [grandparentThumb, parentThumb]
        case "season":
            [grandparentThumb, parentThumb, thumb, art]
        case "track":
            [parentThumb, grandparentThumb, thumb, art]
        default:
            [thumb, parentThumb, grandparentThumb, art]
        }

        return uniqueArtworkPaths(candidates)
    }

    var contentProposalArtworkPaths: [String] {
        uniqueArtworkPaths([thumb, art, parentThumb, grandparentThumb])
    }

    private func uniqueArtworkPaths(_ candidates: [String?]) -> [String] {
        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            guard let path = candidate?.nilIfBlank, seen.insert(path).inserted else {
                return nil
            }
            return path
        }
    }

    var subtitle: String? {
        if type?.lowercased() == "clip", let extraSubtypeLabel {
            return extraSubtypeLabel
        }

        let hierarchy = grandparentTitle ?? parentTitle
        let detail = year.map(String.init) ?? type?.capitalized
        let candidates = [reasonTitle, hierarchy, detail].compactMap { $0?.nilIfBlank }
        var seen: Set<String> = []
        let values = candidates.filter { seen.insert($0).inserted }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    var supportsMediaExtras: Bool {
        type?.lowercased() != "clip"
    }

    var extraSubtypeLabel: String? {
        guard type?.lowercased() == "clip" else {
            return nil
        }

        return switch subtype {
        case "trailer": "Trailer"
        case "deletedScene": "Deleted Scene"
        case "interview": "Interview"
        case "musicVideo": "Music Video"
        case "behindTheScenes": "Behind the Scenes"
        case "sceneOrSample": "Scene or Sample"
        case "liveMusicVideo": "Live Music Video"
        case "lyricMusicVideo": "Lyric Music Video"
        case "concert": "Concert"
        case "featurette": "Featurette"
        case "short": "Short"
        case "other": "Other"
        default: nil
        }
    }

    var primaryExtraActionTitle: String? {
        guard primaryExtraKey?.nilIfBlank != nil else {
            return nil
        }

        return switch type?.lowercased() {
        case "movie": "Trailer"
        case "track": "Music Video"
        default: nil
        }
    }

    var clearLogoPath: String? {
        images.first { $0.type.caseInsensitiveCompare("clearLogo") == .orderedSame }?
            .url
            .nilIfBlank
    }

    private enum CodingKeys: String, CodingKey {
        case ratingKey
        case key
        case guid
        case type
        case subtype
        case title
        case originalTitle
        case reason
        case reasonTitle
        case reasonID
        case parentRatingKey
        case grandparentRatingKey
        case librarySectionID
        case librarySectionTitle
        case parentTitle
        case grandparentTitle
        case year
        case index
        case parentIndex
        case duration
        case summary
        case tagline
        case thumb
        case composite
        case parentThumb
        case grandparentThumb
        case art
        case images = "Image"
        case studio
        case contentRating
        case originallyAvailableAt
        case rating
        case ratingImage
        case audienceRating
        case audienceRatingImage
        case guids = "Guid"
        case ratings = "Rating"
        case userRating
        case viewOffset
        case viewCount
        case leafCount
        case viewedLeafCount
        case childCount
        case skipChildren
        case skipParent
        case primaryExtraKey
        case playQueueItemID
        case playlistItemID
        case playlistType
        case smart
        case readOnly
        case media = "Media"
        case genres = "Genre"
        case directors = "Director"
        case writers = "Writer"
        case producers = "Producer"
        case countries = "Country"
        case roles = "Role"
        case chapters = "Chapter"
        case markers = "Marker"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ratingKey = try values.decodePlexString(forKey: .ratingKey)
        key = try values.decodeIfPresent(String.self, forKey: .key)
        guid = try values.decodeIfPresent(String.self, forKey: .guid)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        subtype = try values.decodeIfPresent(String.self, forKey: .subtype)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        originalTitle = try values.decodeIfPresent(String.self, forKey: .originalTitle)
        reason = try values.decodeIfPresent(String.self, forKey: .reason)
        reasonTitle = try values.decodeIfPresent(String.self, forKey: .reasonTitle)
        reasonID = values.decodePlexStringIfPresent(forKey: .reasonID)
        parentRatingKey = values.decodePlexStringIfPresent(forKey: .parentRatingKey)
        grandparentRatingKey = values.decodePlexStringIfPresent(forKey: .grandparentRatingKey)
        librarySectionID = values.decodePlexStringIfPresent(forKey: .librarySectionID)
        librarySectionTitle = try values.decodeIfPresent(String.self, forKey: .librarySectionTitle)
        parentTitle = try values.decodeIfPresent(String.self, forKey: .parentTitle)
        grandparentTitle = try values.decodeIfPresent(String.self, forKey: .grandparentTitle)
        year = values.decodePlexIntIfPresent(forKey: .year)
        index = values.decodePlexIntIfPresent(forKey: .index)
        parentIndex = values.decodePlexIntIfPresent(forKey: .parentIndex)
        duration = values.decodePlexIntIfPresent(forKey: .duration)
        summary = try values.decodeIfPresent(String.self, forKey: .summary)
        tagline = try values.decodeIfPresent(String.self, forKey: .tagline)
        thumb = try values.decodeIfPresent(String.self, forKey: .thumb)
        composite = try values.decodeIfPresent(String.self, forKey: .composite)
        parentThumb = try values.decodeIfPresent(String.self, forKey: .parentThumb)
        grandparentThumb = try values.decodeIfPresent(String.self, forKey: .grandparentThumb)
        art = try values.decodeIfPresent(String.self, forKey: .art)
        images = try values.decodeIfPresent([PlexMediaImage].self, forKey: .images) ?? []
        studio = try values.decodeIfPresent(String.self, forKey: .studio)
        contentRating = try values.decodeIfPresent(String.self, forKey: .contentRating)
        originallyAvailableAt = try values.decodeIfPresent(String.self, forKey: .originallyAvailableAt)
        rating = values.decodePlexDoubleIfPresent(forKey: .rating)
        ratingImage = try values.decodeIfPresent(String.self, forKey: .ratingImage)
        audienceRating = values.decodePlexDoubleIfPresent(forKey: .audienceRating)
        audienceRatingImage = try values.decodeIfPresent(String.self, forKey: .audienceRatingImage)
        guids = try values.decodeIfPresent([PlexMediaGUID].self, forKey: .guids) ?? []
        ratings = try values.decodeIfPresent([PlexMediaRating].self, forKey: .ratings) ?? []
        userRating = values.decodePlexDoubleIfPresent(forKey: .userRating)
        viewOffset = values.decodePlexIntIfPresent(forKey: .viewOffset)
        viewCount = values.decodePlexIntIfPresent(forKey: .viewCount)
        leafCount = values.decodePlexIntIfPresent(forKey: .leafCount)
        viewedLeafCount = values.decodePlexIntIfPresent(forKey: .viewedLeafCount)
        childCount = values.decodePlexIntIfPresent(forKey: .childCount)
        skipChildren = values.decodePlexBoolIfPresent(forKey: .skipChildren)
        skipParent = values.decodePlexBoolIfPresent(forKey: .skipParent)
        primaryExtraKey = try values.decodeIfPresent(String.self, forKey: .primaryExtraKey)
        playQueueItemID = values.decodePlexStringIfPresent(forKey: .playQueueItemID)
        playlistItemID = values.decodePlexStringIfPresent(forKey: .playlistItemID)
        playlistType = try values.decodeIfPresent(String.self, forKey: .playlistType)
        smart = values.decodePlexBoolIfPresent(forKey: .smart)
        readOnly = values.decodePlexBoolIfPresent(forKey: .readOnly)
        media = try values.decodeIfPresent([PlexMediaVersion].self, forKey: .media) ?? []
        genres = try values.decodeIfPresent([PlexTag].self, forKey: .genres) ?? []
        directors = try values.decodeIfPresent([PlexTag].self, forKey: .directors) ?? []
        writers = try values.decodeIfPresent([PlexTag].self, forKey: .writers) ?? []
        producers = try values.decodeIfPresent([PlexTag].self, forKey: .producers) ?? []
        countries = try values.decodeIfPresent([PlexTag].self, forKey: .countries) ?? []
        roles = try values.decodeIfPresent([PlexTag].self, forKey: .roles) ?? []
        chapters = try values.decodeIfPresent([PlexMediaChapter].self, forKey: .chapters) ?? []
        markers = try values.decodeIfPresent([PlexMediaMarker].self, forKey: .markers) ?? []
    }
}

struct PlexMediaGUID: Decodable, Equatable, Hashable, Sendable {
    let id: String
}

struct PlexMediaRating: Decodable, Equatable, Hashable, Sendable {
    let image: String?
    let type: String?
    let value: Double?

    private enum CodingKeys: String, CodingKey {
        case image
        case type
        case value
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        image = try values.decodeIfPresent(String.self, forKey: .image)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        value = values.decodePlexDoubleIfPresent(forKey: .value)
    }
}

struct PlexMediaImage: Decodable, Equatable, Hashable, Sendable {
    let type: String
    let url: String
    let alt: String?
}

struct PlexMediaVersion: Decodable, Equatable, Hashable, Sendable {
    let id: Int?
    let container: String?
    let videoCodec: String?
    let audioCodec: String?
    let videoResolution: String?
    let width: Int?
    let height: Int?
    let bitrate: Int?
    let duration: Int?
    let selected: Bool?
    let parts: [PlexMediaPart]

    private enum CodingKeys: String, CodingKey {
        case id
        case container
        case videoCodec
        case audioCodec
        case videoResolution
        case width
        case height
        case bitrate
        case duration
        case selected
        case parts = "Part"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexIntIfPresent(forKey: .id)
        container = try values.decodeIfPresent(String.self, forKey: .container)
        videoCodec = try values.decodeIfPresent(String.self, forKey: .videoCodec)
        audioCodec = try values.decodeIfPresent(String.self, forKey: .audioCodec)
        videoResolution = try values.decodeIfPresent(String.self, forKey: .videoResolution)
        width = values.decodePlexIntIfPresent(forKey: .width)
        height = values.decodePlexIntIfPresent(forKey: .height)
        bitrate = values.decodePlexIntIfPresent(forKey: .bitrate)
        duration = values.decodePlexIntIfPresent(forKey: .duration)
        selected = values.decodePlexBoolIfPresent(forKey: .selected)
        parts = try values.decodeIfPresent([PlexMediaPart].self, forKey: .parts) ?? []
    }
}

struct PlexMediaPart: Decodable, Equatable, Hashable, Sendable {
    let id: Int?
    let key: String?
    let container: String?
    let duration: Int?
    let size: Int64?
    let decision: String?
    let selected: Bool?
    let streams: [PlexMediaStream]

    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case container
        case duration
        case size
        case decision
        case selected
        case streams = "Stream"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexIntIfPresent(forKey: .id)
        key = try values.decodeIfPresent(String.self, forKey: .key)
        container = try values.decodeIfPresent(String.self, forKey: .container)
        duration = values.decodePlexIntIfPresent(forKey: .duration)
        size = values.decodePlexInt64IfPresent(forKey: .size)
        decision = try values.decodeIfPresent(String.self, forKey: .decision)
        selected = values.decodePlexBoolIfPresent(forKey: .selected)
        streams = try values.decodeIfPresent([PlexMediaStream].self, forKey: .streams) ?? []
    }
}

struct PlexMediaStream: Decodable, Equatable, Hashable, Sendable {
    let id: Int?
    let streamType: Int?
    let codec: String?
    let language: String?
    let languageCode: String?
    let displayTitle: String?
    let title: String?
    let channels: Int?
    let selected: Bool?
    let forced: Bool?
    let hearingImpaired: Bool?
    let visualImpaired: Bool?
    let canAutoSync: Bool?
    let offset: Int?
    let decision: String?
    let location: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case streamType
        case codec
        case language
        case languageCode
        case displayTitle
        case title
        case channels
        case selected
        case forced
        case hearingImpaired
        case visualImpaired
        case canAutoSync
        case offset
        case decision
        case location
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexIntIfPresent(forKey: .id)
        streamType = values.decodePlexIntIfPresent(forKey: .streamType)
        codec = try values.decodeIfPresent(String.self, forKey: .codec)
        language = try values.decodeIfPresent(String.self, forKey: .language)
        languageCode = try values.decodeIfPresent(String.self, forKey: .languageCode)
        displayTitle = try values.decodeIfPresent(String.self, forKey: .displayTitle)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        channels = values.decodePlexIntIfPresent(forKey: .channels)
        selected = values.decodePlexBoolIfPresent(forKey: .selected)
        forced = values.decodePlexBoolIfPresent(forKey: .forced)
        hearingImpaired = values.decodePlexBoolIfPresent(forKey: .hearingImpaired)
        visualImpaired = values.decodePlexBoolIfPresent(forKey: .visualImpaired)
        canAutoSync = values.decodePlexBoolIfPresent(forKey: .canAutoSync)
        offset = values.decodePlexIntIfPresent(forKey: .offset)
        decision = try values.decodeIfPresent(String.self, forKey: .decision)
        location = try values.decodeIfPresent(String.self, forKey: .location)
    }
}

struct PlexTag: Decodable, Equatable, Hashable, Sendable {
    let id: Int?
    let tag: String
    let tagKey: String?
    let tagType: Int?
    let filter: String?
    let role: String?
    let thumb: String?
    let order: Int?

    init(
        id: Int? = nil,
        tag: String,
        tagKey: String? = nil,
        tagType: Int? = nil,
        filter: String? = nil,
        role: String? = nil,
        thumb: String? = nil,
        order: Int? = nil
    ) {
        self.id = id
        self.tag = tag
        self.tagKey = tagKey
        self.tagType = tagType
        self.filter = filter
        self.role = role
        self.thumb = thumb
        self.order = order
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case tag
        case tagKey
        case tagType
        case filter
        case role
        case thumb
        case order
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexIntIfPresent(forKey: .id)
        tag = try values.decodeIfPresent(String.self, forKey: .tag) ?? ""
        tagKey = values.decodePlexStringIfPresent(forKey: .tagKey)
        tagType = values.decodePlexIntIfPresent(forKey: .tagType)
        filter = try values.decodeIfPresent(String.self, forKey: .filter)
        role = try values.decodeIfPresent(String.self, forKey: .role)
        thumb = try values.decodeIfPresent(String.self, forKey: .thumb)
        order = values.decodePlexIntIfPresent(forKey: .order)
    }
}

struct PlexPeopleEnvelope: Decodable, Sendable {
    let mediaContainer: PlexPeopleContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexPeopleContainer: Decodable, Sendable {
    let people: [PlexTag]

    enum CodingKeys: String, CodingKey {
        case people = "Directory"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        people = try values.decodeIfPresent([PlexTag].self, forKey: .people) ?? []
    }
}

struct PlexMediaPage: Equatable, Sendable {
    let items: [PlexMediaItem]
    let offset: Int
    let totalSize: Int?
}

struct PlexMediaEnvelope: Decodable, Sendable {
    let mediaContainer: PlexMediaContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexMediaContainer: Decodable, Sendable {
    let size: Int?
    let totalSize: Int?
    let offset: Int?
    let metadata: [PlexMediaItem]

    enum CodingKeys: String, CodingKey {
        case size
        case totalSize
        case offset
        case metadata = "Metadata"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        size = values.decodePlexIntIfPresent(forKey: .size)
        totalSize = values.decodePlexIntIfPresent(forKey: .totalSize)
        offset = values.decodePlexIntIfPresent(forKey: .offset)
        metadata = try values.decodeIfPresent([PlexMediaItem].self, forKey: .metadata) ?? []
    }
}

extension KeyedDecodingContainer {
    func decodePlexString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected a Plex string or integer value."
            )
        )
    }

    func decodePlexStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodePlexIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodePlexInt64IfPresent(forKey key: Key) -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int64(value)
        }
        return nil
    }

    func decodePlexDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func decodePlexBoolIfPresent(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = decodePlexIntIfPresent(forKey: key) {
            return value != 0
        }
        return nil
    }
}
