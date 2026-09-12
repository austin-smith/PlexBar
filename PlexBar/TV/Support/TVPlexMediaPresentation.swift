import Foundation

extension PlexMediaItem {
    var tvCanStartPlayback: Bool {
        if isPlayable || supportsHierarchyPlayback { return true }
        // Hub and search responses may omit Media; preparation loads full metadata.
        switch type?.lowercased() {
        case "movie", "episode", "clip", "track": return true
        default: return false
        }
    }

    var displayTitle: String { title }

    var contextTitle: String? {
        switch type?.lowercased() {
        case "episode": grandparentTitle
        case "track": parentTitle ?? grandparentTitle
        default: nil
        }
    }

    var resumeSeconds: TimeInterval {
        TimeInterval(viewOffset ?? 0) / 1_000
    }

    var durationSeconds: TimeInterval {
        TimeInterval(duration ?? 0) / 1_000
    }

    var preferredLandscapePath: String? {
        type?.lowercased() == "episode" ? thumb ?? art : preferredBackdropPath
    }

    var preferredBackdropPath: String? {
        art ?? thumb ?? grandparentThumb ?? parentThumb ?? composite
    }

    var tvEpisodeTitle: String? {
        guard type?.lowercased() == "episode" else { return nil }
        return PlexMediaSummaryPresentation(item: self).episodeHeading
    }

    var tvResumeTitle: String? {
        guard resumeSeconds > 0 else { return nil }
        return "Resume " + Duration.seconds(resumeSeconds).formatted(.time(pattern: .hourMinuteSecond))
    }

    var metadataLine: String {
        factsLine ?? ""
    }
}
