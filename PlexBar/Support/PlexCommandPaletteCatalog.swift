import PlexClientKit
import PlexModels

@MainActor
enum PlexCommandPaletteCatalog {
    static func commands(
        libraries: [PlexLibrary],
        hasConfiguration: Bool,
        player: PlexPlayerCoordinator,
        search: PlexFocusedCommandAction?,
        refresh: PlexFocusedCommandAction?,
        info: PlexFocusedCommandAction?,
        upNext: PlexFocusedCommandAction?,
        closePlayer: PlexFocusedCommandAction?
    ) -> [PlexPaletteCommand] {
        var commands: [PlexPaletteCommand] = []
        if player.presentation == nil {
            if let search {
                commands.append(.init(
                    id: .search, title: search.title, systemImage: "magnifyingglass", group: .currentView,
                    keywords: ["find", "search", "all libraries"], shortcut: "⌘F",
                    unavailableReason: search.isEnabled ? nil : "Connect to a Plex server to search"
                ))
            }
            if let refresh {
                commands.append(.init(
                    id: .refresh, title: refresh.title, systemImage: "arrow.clockwise", group: .currentView,
                    keywords: ["reload", "update"], shortcut: "⌘R",
                    unavailableReason: refresh.isEnabled ? nil : "Refresh is unavailable in this view"
                ))
            }
        } else {
            if let transport = player.transportAction {
                commands.append(.init(
                    id: .togglePlayback, title: transport == .pause ? "Pause Playback" : "Resume Playback",
                    systemImage: transport == .pause ? "pause.fill" : "play.fill", group: .playback,
                    keywords: ["play", "pause", "resume"], shortcut: "Space"
                ))
            }
            if player.canGoPrevious {
                commands.append(.init(id: .previous, title: "Play Previous Item", systemImage: "backward.end.fill",
                                      group: .playback, keywords: ["previous", "queue"], shortcut: "⌘←"))
            }
            if player.canGoNext {
                commands.append(.init(id: .next, title: "Play Next Item", systemImage: "forward.end.fill",
                                      group: .playback, keywords: ["next", "queue"], shortcut: "⌘→"))
            }
            if player.canSeek {
                commands.append(.init(id: .skipBackward, title: "Skip Backward 10 Seconds", systemImage: "gobackward.10",
                                      group: .playback, keywords: ["rewind", "seek"], shortcut: "←"))
                commands.append(.init(id: .skipForward, title: "Skip Forward 10 Seconds", systemImage: "goforward.10",
                                      group: .playback, keywords: ["seek", "fast forward"], shortcut: "→"))
            }
            if let info, info.isEnabled {
                commands.append(.init(id: .playerInfo, title: info.title, systemImage: "info.circle",
                                      group: .playback, keywords: ["details", "information"], shortcut: "⌘I"))
            }
            if let upNext, upNext.isEnabled {
                commands.append(.init(id: .playerUpNext, title: upNext.title, systemImage: "list.bullet",
                                      group: .playback, keywords: ["queue", "up next"]))
            }
            if let closePlayer, closePlayer.isEnabled {
                commands.append(.init(id: .closePlayer, title: closePlayer.title, systemImage: "stop.fill",
                                      group: .playback, keywords: ["back", "close", "stop", "library"]))
            }
        }

        let playbackReason = player.presentation == nil ? nil : "Stop playback and return to the library first"
        let serverReason = hasConfiguration ? nil : "Connect to a Plex server first"
        for section: PlexMainSection in [.home, .downloads, .collections, .playlists, .activity, .history, .users] {
            commands.append(.init(
                id: .navigate(section), title: "Open \(section.title)", systemImage: section.systemImage,
                group: .navigation, keywords: [section.title],
                unavailableReason: playbackReason ?? (section == .home || section == .downloads ? nil : serverReason)
            ))
        }
        for library in libraries {
            commands.append(.init(
                id: .navigate(.library(library.id)), title: "Open \(library.title)",
                systemImage: library.type.symbolName, group: .libraries, keywords: [library.title, "library"],
                unavailableReason: playbackReason ?? serverReason
            ))
        }
        commands.append(.init(id: .settings, title: "Open Settings", systemImage: "gearshape", group: .app,
                              keywords: ["settings", "preferences", "account", "server", "configuration"], shortcut: "⌘,"))
        return commands
    }
}
