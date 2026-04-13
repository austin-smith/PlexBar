import Foundation

struct PlexServerPreview: Equatable {
    let serverID: String
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

    static let empty = PlexServerPreviewState()
}
