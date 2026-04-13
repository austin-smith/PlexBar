import Foundation

struct PlexLibrary: Identifiable, Equatable {
    let id: String
    let title: String
    let type: PlexLibraryType
    let compositePath: String?
    let artPath: String?
    let thumbPath: String?
    let itemCount: Int
    let secondaryCount: Int?
    let secondaryCountLabel: String?
    let updatedAt: Date?
    let scannedAt: Date?
    let contentChangedAt: Date?
    let latestAddedAt: Date?
    let latestItemTitle: String?

    var sortDate: Date {
        latestAddedAt ?? contentChangedAt ?? scannedAt ?? updatedAt ?? .distantPast
    }

    var itemSummary: String {
        guard let secondaryCount, let secondaryCountLabel else {
            return "\(itemCount.formatted()) \(type.itemLabel(for: itemCount))"
        }

        let primaryLabel = "\(itemCount.formatted()) \(type.itemLabel(for: itemCount))"
        let secondaryLabel = "\(secondaryCount.formatted()) \(secondaryCountLabel)"
        return "\(primaryLabel) • \(secondaryLabel)"
    }

    var primaryItemSummary: String {
        "\(itemCount.formatted()) \(type.itemLabel(for: itemCount))"
    }

    var statusDate: Date? {
        latestAddedAt ?? contentChangedAt ?? scannedAt ?? updatedAt
    }

    var statusPrefix: String {
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
}

enum PlexLibraryType: Equatable {
    case movie
    case show
    case artist
    case album
    case photo
    case photoAlbum
    case clip
    case unknown(String)

    init(rawValue: String) {
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

    var displayName: String {
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

    var symbolName: String {
        switch self {
        case .movie:
            "film"
        case .show:
            "tv"
        case .artist, .album:
            "music.note.list"
        case .photo, .photoAlbum:
            "photo.on.rectangle"
        case .clip:
            "play.rectangle"
        case .unknown:
            "books.vertical"
        }
    }

    func itemLabel(for count: Int) -> String {
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

    var preferredSecondarySummary: (queryType: Int, label: String)? {
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
