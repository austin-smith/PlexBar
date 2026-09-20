import Foundation

public enum PlexMediaIcon: Equatable, Sendable {
    case movie
    case show
    case music
    case photo
    case clip
    case liveTV
    case other
    case library

    public var symbolName: String {
        switch self {
        case .movie:
            "film"
        case .show:
            "tv"
        case .music:
            "music.note.list"
        case .photo:
            "photo.on.rectangle"
        case .clip:
            "play.rectangle"
        case .liveTV:
            "antenna.radiowaves.left.and.right"
        case .other:
            "play.square"
        case .library:
            "books.vertical"
        }
    }
}

public struct PlexLibrary: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let type: PlexLibraryType
    public let compositePath: String?
    public let artPath: String?
    public let thumbPath: String?
    public let itemCount: Int
    public let secondaryCount: Int?
    public let secondaryCountLabel: String?
    public let updatedAt: Date?
    public let scannedAt: Date?
    public let contentChangedAt: Date?
    public let latestAddedAt: Date?
    public let latestItemTitle: String?
    public var allowSync: Bool? = nil

    public var sortDate: Date {
        latestAddedAt ?? contentChangedAt ?? scannedAt ?? updatedAt ?? .distantPast
    }

    public var itemSummary: String {
        guard let secondaryCount, let secondaryCountLabel else {
            return "\(itemCount.formatted()) \(type.itemLabel(for: itemCount))"
        }

        let primaryLabel = "\(itemCount.formatted()) \(type.itemLabel(for: itemCount))"
        let secondaryLabel = "\(secondaryCount.formatted()) \(secondaryCountLabel)"
        return "\(primaryLabel) • \(secondaryLabel)"
    }

    public var primaryItemSummary: String {
        "\(itemCount.formatted()) \(type.itemLabel(for: itemCount))"
    }

    public var statusDate: Date? {
        latestAddedAt ?? contentChangedAt ?? scannedAt ?? updatedAt
    }

    public var statusPrefix: String {
        if latestAddedAt != nil {
            return "Latest add"
        }

        if contentChangedAt != nil {
            return "Updated"
        }

        if scannedAt != nil {
            return "Scanned"
        }

        return "Updated"
    }

    public init(
        id: String,
        title: String,
        type: PlexLibraryType,
        compositePath: String? = nil,
        artPath: String? = nil,
        thumbPath: String? = nil,
        itemCount: Int,
        secondaryCount: Int? = nil,
        secondaryCountLabel: String? = nil,
        updatedAt: Date? = nil,
        scannedAt: Date? = nil,
        contentChangedAt: Date? = nil,
        latestAddedAt: Date? = nil,
        latestItemTitle: String? = nil,
        allowSync: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.compositePath = compositePath
        self.artPath = artPath
        self.thumbPath = thumbPath
        self.itemCount = itemCount
        self.secondaryCount = secondaryCount
        self.secondaryCountLabel = secondaryCountLabel
        self.updatedAt = updatedAt
        self.scannedAt = scannedAt
        self.contentChangedAt = contentChangedAt
        self.latestAddedAt = latestAddedAt
        self.latestItemTitle = latestItemTitle
        self.allowSync = allowSync
    }
}

public enum PlexLibraryType: Equatable, Sendable {
    case movie
    case show
    case artist
    case album
    case photo
    case photoAlbum
    case clip
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "movie":
            self = .movie
        case "show":
            self = .show
        case "artist":
            self = .artist
        case "album":
            self = .album
        case "photo":
            self = .photo
        case "photoalbum":
            self = .photoAlbum
        case "clip":
            self = .clip
        default:
            self = .unknown(rawValue)
        }
    }

    public var displayName: String {
        switch self {
        case .movie:
            "Movies"
        case .show:
            "TV Shows"
        case .artist:
            "Music"
        case .album:
            "Albums"
        case .photo:
            "Photos"
        case .photoAlbum:
            "Photo Albums"
        case .clip:
            "Clips"
        case .unknown:
            "Library"
        }
    }

    public var symbolName: String {
        icon.symbolName
    }

    private var icon: PlexMediaIcon {
        switch self {
        case .movie:
            .movie
        case .show:
            .show
        case .artist, .album:
            .music
        case .photo, .photoAlbum:
            .photo
        case .clip:
            .clip
        case .unknown:
            .library
        }
    }

    public func itemLabel(for count: Int) -> String {
        switch self {
        case .movie:
            count == 1 ? "movie" : "movies"
        case .show:
            count == 1 ? "show" : "shows"
        case .artist:
            count == 1 ? "artist" : "artists"
        case .album:
            count == 1 ? "album" : "albums"
        case .photo:
            count == 1 ? "photo" : "photos"
        case .photoAlbum:
            count == 1 ? "album" : "albums"
        case .clip:
            count == 1 ? "clip" : "clips"
        case .unknown:
            count == 1 ? "item" : "items"
        }
    }

    public var preferredSecondarySummary: (queryType: Int, label: String)? {
        switch self {
        case .show:
            return (3, "seasons")
        case .artist:
            return (9, "albums")
        default:
            return nil
        }
    }
}
