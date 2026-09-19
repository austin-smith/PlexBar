import Foundation

public struct PlexMediaItem: Decodable, Equatable, Hashable, Identifiable, Sendable {
    public let ratingKey: String
    public let key: String?
    public let guid: String?
    public let type: String?
    public let subtype: String?
    public let title: String
    public let originalTitle: String?
    public let reason: String?
    public let reasonTitle: String?
    public let reasonID: String?
    public let parentRatingKey: String?
    public let grandparentRatingKey: String?
    public let librarySectionID: String?
    public let librarySectionTitle: String?
    public let parentTitle: String?
    public let grandparentTitle: String?
    public let year: Int?
    public let index: Int?
    public let parentIndex: Int?
    public let duration: Int?
    public let summary: String?
    public let thumb: String?
    public let composite: String?
    public let parentThumb: String?
    public let grandparentThumb: String?
    public let art: String?
    public let images: [PlexMediaImage]
    public let studio: String?
    public let contentRating: String?
    public let originallyAvailableAt: String?
    public let rating: Double?
    public let ratingImage: String?
    public let audienceRating: Double?
    public let audienceRatingImage: String?
    public let guids: [PlexMediaGUID]
    public let ratings: [PlexMediaRating]
    public var userRating: Double?
    public var viewOffset: Int?
    public var viewCount: Int?
    public let leafCount: Int?
    public var viewedLeafCount: Int?
    public let childCount: Int?
    public let skipChildren: Bool?
    public let skipParent: Bool?
    public let primaryExtraKey: String?
    public let playQueueItemID: String?
    public let playlistItemID: String?
    public let playlistType: String?
    public let smart: Bool?
    public let readOnly: Bool?
    public let media: [PlexMediaVersion]
    public let genres: [PlexTag]
    public let directors: [PlexTag]
    public let writers: [PlexTag]
    public let producers: [PlexTag]
    public let countries: [PlexTag]
    public let roles: [PlexTag]
    public let chapters: [PlexMediaChapter]
    public let markers: [PlexMediaMarker]

    public var id: String {
        playQueueItemID.map { "play-queue-item:\($0)" }
            ?? playlistItemID.map { "playlist-item:\($0)" }
            ?? ratingKey
    }

    public var isPlayable: Bool {
        supportsNativePlayback && media.contains { !$0.parts.isEmpty }
    }

    public var supportsNativePlayback: Bool {
        type?.lowercased() != "photo"
    }

    public var hasChildren: Bool {
        guard let type = type?.lowercased() else {
            return false
        }

        return [
            "show", "season", "artist", "album", "photoalbum", "collection", "playlist",
            "playlistfolder"
        ].contains(type)
    }

    public var childrenPath: String? {
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

    public func hierarchyRequestItem(afterRefreshingWith details: PlexMediaItem) -> PlexMediaItem {
        guard ratingKey == details.ratingKey,
              childrenPath == nil,
              details.childrenPath != nil else {
            return self
        }
        return details
    }

    public var progress: Double? {
        guard let duration, duration > 0, let viewOffset else {
            return nil
        }

        return min(max(Double(viewOffset) / Double(duration), 0), 1)
    }

    public var isWatched: Bool {
        if let leafCount, leafCount > 0, let viewedLeafCount {
            return viewedLeafCount >= leafCount
        }
        return (viewCount ?? 0) > 0
    }

    public var supportsWatchedStateMutation: Bool {
        guard let type = type?.lowercased() else {
            return false
        }
        return ["movie", "show", "season", "episode"].contains(type)
    }

    public var supportsPlaybackHistory: Bool {
        guard Int(ratingKey) != nil, let type = type?.lowercased() else {
            return false
        }

        return ["movie", "show", "season", "episode", "artist", "album", "track"].contains(type)
    }

    public func mergingWatchedState(from refreshedItem: PlexMediaItem) -> PlexMediaItem {
        guard ratingKey == refreshedItem.ratingKey else {
            return self
        }

        var merged = self
        merged.viewOffset = refreshedItem.viewOffset
        merged.viewCount = refreshedItem.viewCount
        merged.viewedLeafCount = refreshedItem.viewedLeafCount
        return merged
    }

    public func mergingUserRating(from refreshedItem: PlexMediaItem) -> PlexMediaItem {
        guard ratingKey == refreshedItem.ratingKey else {
            return self
        }

        var merged = self
        merged.userRating = refreshedItem.userRating
        return merged
    }

    public var supportsMetadataRefresh: Bool {
        guard let type = type?.lowercased() else {
            return false
        }
        return [
            "movie", "show", "season", "episode", "artist", "album", "track", "photo", "photoalbum"
        ].contains(type)
    }

    public var preferredArtworkPath: String? {
        thumb?.nilIfBlank ?? composite?.nilIfBlank
    }

    public var formattedDuration: String? {
        guard let duration, duration > 0 else {
            return nil
        }

        let roundedMinutes = max((Int64(duration) + 30_000) / 60_000, 1)
        return Duration.seconds(roundedMinutes * 60)
            .formatted(.units(width: .abbreviated))
            .replacingOccurrences(of: ", ", with: " ")
    }

    public var posterArtworkPath: String? {
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

    public var nowPlayingArtworkPaths: [String] {
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

    public var contentProposalArtworkPaths: [String] {
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

    public var subtitle: String? {
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

    public var supportsMediaExtras: Bool {
        type?.lowercased() != "clip"
    }

    public var extraSubtypeLabel: String? {
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

    public var primaryExtraActionTitle: String? {
        guard primaryExtraKey?.nilIfBlank != nil else {
            return nil
        }

        return switch type?.lowercased() {
        case "movie": "Trailer"
        case "track": "Music Video"
        default: nil
        }
    }

    public var clearLogoPath: String? {
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

    public init(from decoder: Decoder) throws {
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

public struct PlexMediaGUID: Decodable, Equatable, Hashable, Sendable {
    public let id: String

    public init(
        id: String
    ) {
        self.id = id
    }
}

public struct PlexMediaRating: Decodable, Equatable, Hashable, Sendable {
    public let image: String?
    public let type: String?
    public let value: Double?

    private enum CodingKeys: String, CodingKey {
        case image
        case type
        case value
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        image = try values.decodeIfPresent(String.self, forKey: .image)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        value = values.decodePlexDoubleIfPresent(forKey: .value)
    }
}

public struct PlexMediaImage: Decodable, Equatable, Hashable, Sendable {
    public let type: String
    public let url: String
    public let alt: String?

    public init(
        type: String,
        url: String,
        alt: String? = nil
    ) {
        self.type = type
        self.url = url
        self.alt = alt
    }
}

public struct PlexMediaVersion: Decodable, Equatable, Hashable, Sendable {
    public let id: Int?
    public let container: String?
    public let videoCodec: String?
    public let audioCodec: String?
    public let videoResolution: String?
    public let width: Int?
    public let height: Int?
    public let bitrate: Int?
    public let duration: Int?
    public let selected: Bool?
    public let parts: [PlexMediaPart]

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

    public init(from decoder: Decoder) throws {
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

public struct PlexMediaPart: Decodable, Equatable, Hashable, Sendable {
    public let id: Int?
    public let key: String?
    public let container: String?
    public let duration: Int?
    public let size: Int64?
    public let decision: String?
    public let selected: Bool?
    public let indexes: String?
    public let streams: [PlexMediaStream]

    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case container
        case duration
        case size
        case decision
        case selected
        case indexes
        case streams = "Stream"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexIntIfPresent(forKey: .id)
        key = try values.decodeIfPresent(String.self, forKey: .key)
        container = try values.decodeIfPresent(String.self, forKey: .container)
        duration = values.decodePlexIntIfPresent(forKey: .duration)
        size = values.decodePlexInt64IfPresent(forKey: .size)
        decision = try values.decodeIfPresent(String.self, forKey: .decision)
        selected = values.decodePlexBoolIfPresent(forKey: .selected)
        indexes = try values.decodeIfPresent(String.self, forKey: .indexes)
        streams = try values.decodeIfPresent([PlexMediaStream].self, forKey: .streams) ?? []
    }
}

public struct PlexMediaStream: Decodable, Equatable, Hashable, Sendable {
    public let id: Int?
    public let streamType: Int?
    public let codec: String?
    public let language: String?
    public let languageCode: String?
    public let displayTitle: String?
    public let title: String?
    public let channels: Int?
    public let selected: Bool?
    public let forced: Bool?
    public let hearingImpaired: Bool?
    public let visualImpaired: Bool?
    public let canAutoSync: Bool?
    public let offset: Int?
    public let decision: String?
    public let location: String?

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

    public init(from decoder: Decoder) throws {
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

public struct PlexTag: Decodable, Equatable, Hashable, Sendable {
    public let id: Int?
    public let tag: String
    public let tagKey: String?
    public let tagType: Int?
    public let filter: String?
    public let role: String?
    public let thumb: String?
    public let order: Int?

    public init(
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

    public init(from decoder: Decoder) throws {
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

public struct PlexPeopleEnvelope: Decodable, Sendable {
    public let mediaContainer: PlexPeopleContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    public init(
        mediaContainer: PlexPeopleContainer
    ) {
        self.mediaContainer = mediaContainer
    }
}

public struct PlexPeopleContainer: Decodable, Sendable {
    public let people: [PlexTag]

    enum CodingKeys: String, CodingKey {
        case people = "Directory"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        people = try values.decodeIfPresent([PlexTag].self, forKey: .people) ?? []
    }
}

public struct PlexMediaPage: Equatable, Sendable {
    public let items: [PlexMediaItem]
    public let offset: Int
    public let totalSize: Int?

    public init(
        items: [PlexMediaItem],
        offset: Int,
        totalSize: Int? = nil
    ) {
        self.items = items
        self.offset = offset
        self.totalSize = totalSize
    }
}

public struct PlexMediaEnvelope: Decodable, Sendable {
    public let mediaContainer: PlexMediaContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    public init(
        mediaContainer: PlexMediaContainer
    ) {
        self.mediaContainer = mediaContainer
    }
}

public struct PlexMediaContainer: Decodable, Sendable {
    public let size: Int?
    public let totalSize: Int?
    public let offset: Int?
    public let metadata: [PlexMediaItem]

    enum CodingKeys: String, CodingKey {
        case size
        case totalSize
        case offset
        case metadata = "Metadata"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        size = values.decodePlexIntIfPresent(forKey: .size)
        totalSize = values.decodePlexIntIfPresent(forKey: .totalSize)
        offset = values.decodePlexIntIfPresent(forKey: .offset)
        metadata = try values.decodeIfPresent([PlexMediaItem].self, forKey: .metadata) ?? []
    }
}
