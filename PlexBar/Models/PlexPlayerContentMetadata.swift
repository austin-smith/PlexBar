import PlexClientKit
import PlexModels

/// Reuses the existing content presentations for the compact player header.
struct PlexPlayerContentMetadata {
    let title: String?
    let details: [String]

    init(item: PlexMediaItem, source: PlexPlaybackSource) {
        if let audio = PlexAudioPlaybackPresentation(item: item, source: source) {
            title = audio.title
            details = audio.metadataLines
        } else if item.type?.lowercased() == "episode" {
            title = item.grandparentTitle?.nilIfBlank
            details = [PlexMediaSummaryPresentation(item: item).episodeHeading]
        } else {
            title = item.title
            details = [item.subtitle].compactMap { $0 }
        }
    }
}
