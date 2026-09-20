import Foundation

struct PlexPaletteCommand: Identifiable, Equatable {
    enum ID: Hashable {
        case navigate(PlexMainSection)
        case search, refresh, settings
        case togglePlayback, previous, next, skipBackward, skipForward
        case playerInfo, playerUpNext, closePlayer
    }

    enum Group: String, CaseIterable {
        case currentView = "Current View"
        case playback = "Playback"
        case navigation = "Go To"
        case libraries = "Libraries"
        case app = "App"
    }

    let id: ID
    let title: String
    let systemImage: String
    let group: Group
    var keywords: [String] = []
    var shortcut: String? = nil
    var unavailableReason: String? = nil

    var isEnabled: Bool { unavailableReason == nil }

    func matchesExactly(_ query: String) -> Bool {
        let query = Self.normalized(query)
        return !query.isEmpty && (Self.normalized(title) == query || keywords.map(Self.normalized).contains(query))
    }

    /// Explicit matching tiers, with catalog order as the stable tie breaker.
    static func matching(_ commands: [Self], query: String) -> [Self] {
        let query = normalized(query)
        guard !query.isEmpty else { return commands }
        let tokens = query.split(whereSeparator: \.isWhitespace)
        return commands.enumerated().compactMap { index, command -> (Int, Int, Self)? in
            let title = normalized(command.title)
            let keywords = command.keywords.map(normalized)
            let searchableText = ([title] + keywords).joined(separator: " ")
            guard tokens.allSatisfy({ searchableText.contains($0) }) else { return nil }
            let rank = title == query ? 0 : title.hasPrefix(query) ? 1 : keywords.contains(query) ? 2 : 3
            return (rank, index, command)
        }
        .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
        .map(\.2)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
