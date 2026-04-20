import Foundation

struct PlexServerPreview: Equatable {
    let serverID: String
    let serverURL: URL
    let items: [PlexServerPreviewItem]
    let generatedAt: Date
}

struct PlexServerPreviewItem: Identifiable, Equatable {
    let id: String
    let title: String
    let posterPath: String?
    let artworkPath: String?
    let addedAt: Date

    var hasArtwork: Bool {
        posterPath != nil || artworkPath != nil
    }
}

struct PlexServerPreviewState: Equatable {
    var preview: PlexServerPreview?
    var isLoading = false
    var hasLoaded = false
    var errorMessage: String?

    var items: [PlexServerPreviewItem] {
        preview?.items ?? []
    }

    var serverURL: URL? {
        preview?.serverURL
    }

    static let empty = PlexServerPreviewState()
}
