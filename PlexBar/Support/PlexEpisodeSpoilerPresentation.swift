import Foundation

enum PlexEpisodeSpoilerPolicy: String, CaseIterable, Identifiable, Sendable {
    case off
    case unwatchedEpisodes
    case allEpisodes

    var id: Self { self }

    var label: String {
        switch self {
        case .off: "Off"
        case .unwatchedEpisodes: "Unwatched Episodes"
        case .allEpisodes: "All Episodes"
        }
    }

    func hidesSpoilers(for item: PlexMediaItem) -> Bool {
        guard item.type?.lowercased() == "episode" else {
            return false
        }

        switch self {
        case .off:
            return false
        case .unwatchedEpisodes:
            return (item.viewCount ?? 0) == 0
        case .allEpisodes:
            return true
        }
    }
}

struct PlexEpisodeSpoilerPresentation: Equatable, Sendable {
    let isProtected: Bool
    let summary: String?
    let thumbnailPath: String?

    init(item: PlexMediaItem, policy: PlexEpisodeSpoilerPolicy) {
        isProtected = policy.hidesSpoilers(for: item)
        summary = isProtected ? nil : item.summary?.nilIfBlank
        thumbnailPath = isProtected ? nil : item.preferredArtworkPath
    }
}
