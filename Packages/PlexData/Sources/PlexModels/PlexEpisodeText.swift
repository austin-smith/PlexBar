import Foundation

public enum PlexEpisodeText: Sendable {
    public static func numbers(season: Int?, episode: Int?) -> String? {
        [season.map { "S\($0)" }, episode.map { "E\($0)" }]
            .compactMap { $0 }
            .joined(separator: " • ")
            .nilIfBlank
    }

    public static func subtitle(season: Int?, episode: Int?, title: String) -> String {
        [numbers(season: season, episode: episode), title.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " - ")
    }
}
