import PlexClientKit
import PlexModels
import SwiftUI

extension EnvironmentValues {
    @Entry var isPlexCommandPalettePresented = false
}

struct PlexCommandPaletteHost: ViewModifier {
    @Bindable var store: PlexCommandPaletteStore
    let settingsStore: PlexSettingsStore
    let connectionStore: PlexConnectionStore
    let libraryStore: PlexLibraryStore
    let browserStore: PlexBrowserStore
    let downloadsStore: PlexDownloadsStore
    let playerCoordinator: PlexPlayerCoordinator
    let navigate: (PlexMainSection) -> Void
    let openResult: (PlexPaletteResult, String, [PlexHub]) -> Void
    @Environment(\.openSettings) private var openSettings
    @FocusedValue(\.plexSearchCommand) private var search
    @FocusedValue(\.plexRefreshCommand) private var refresh
    @FocusedValue(\.plexPlayerInfoCommand) private var info
    @FocusedValue(\.plexPlayerUpNextCommand) private var upNext
    @FocusedValue(\.plexPlayerCloseCommand) private var closePlayer
    @State private var windowContext = PlexCommandPaletteWindowContext()

    private var commands: [PlexPaletteCommand] {
        PlexCommandPaletteCatalog.commands(
            libraries: libraryStore.libraries,
            hasConfiguration: settingsStore.hasValidConfiguration,
            player: playerCoordinator,
            search: search, refresh: refresh, info: info, upNext: upNext, closePlayer: closePlayer
        )
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(store.isPresented)

            if store.isPresented {
                ZStack {
                    Button(action: { windowContext.dismiss() }) {
                        Color.black.opacity(0.12)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityHidden(true)

                    GeometryReader { geometry in
                        PlexCommandPaletteView(
                            store: store,
                            settingsStore: settingsStore,
                            serverURL: connectionStore.resolvedServerURL,
                            maximumResultsHeight: max(100, min(420, geometry.size.height * 0.95 - 150)),
                            isComposingText: { windowContext.isComposingText },
                            dismiss: { windowContext.dismiss() },
                            execute: execute,
                            play: play
                        )
                        .padding(.horizontal, 24)
                        // Anchor the search field while filtered results resize below it.
                        .padding(.top, geometry.size.height * 0.05)
                        .padding(.bottom, 24)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    }
                }
                .onDisappear { windowContext.presentationDidDisappear() }
            }
        }
        .background {
            PlexCommandPaletteWindowReader(context: windowContext, store: store)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onChange(of: commands, initial: true) { _, commands in
            store.updateCommands(commands)
        }
        .onChange(of: searchContext, initial: true) { _, context in
            store.configure(
                scope: context.scope, canSearch: context.canSearch, suggestions: context.suggestions,
                libraries: context.libraries, downloads: context.downloads
            ) { query in
                try await browserStore.searchAllLibraries(query: query, limit: 4)
            }
        }
        .onChange(of: connectionStore.accountCacheScope) {
            windowContext.dismiss(restoringFocus: false)
        }
        .onChange(of: playerCoordinator.presentation?.id) {
            windowContext.dismiss(restoringFocus: false)
        }
    }

    private var searchContext: SearchContext {
        SearchContext(scope: connectionStore.accountCacheScope, canSearch: settingsStore.hasValidConfiguration,
                      suggestions: browserStore.homeState.hubs.filter(\.isContinueWatching).flatMap(\.metadata),
                      libraries: libraryStore.libraries, downloads: downloadsStore.searchableDownloadedMedia)
    }

    private struct SearchContext: Equatable {
        let scope: String
        let canSearch: Bool
        let suggestions: [PlexMediaItem]
        let libraries: [PlexLibrary]
        let downloads: [PlexOfflineMedia]
    }

    private func execute(_ result: PlexPaletteResult) {
        guard store.isPresented, !store.isPreparingPlayback, result.isEnabled else { return }
        if case .command(let command) = result.content {
            executeCommand(command.id)
            return
        }
        let query = store.searchQuery
        let hubs = store.hubs
        if case .media(let item, _) = result.content { store.remember(item) }
        windowContext.dismiss(restoringFocus: false) { openResult(result, query, hubs) }
    }

    private func play(_ result: PlexPaletteResult) {
        guard !windowContext.isComposingText, case .media(let item, let download) = result.content else { return }
        store.preparePlayback(result, prepare: {
            if let download { return try await downloadsStore.playbackPresentation(for: download) }
            let resolved = try await browserStore.refreshedPlayableDetails(for: item)
            try Task.checkCancellation()
            return try await PlexMediaPlaybackPreparation(
                browserStore: browserStore, settingsStore: settingsStore, connectionStore: connectionStore
            ).prepare(for: resolved, startOption: resolved.hasResumePosition ? .resume : .beginning,
                      videoQuality: settingsStore.videoQuality(for: connectionStore.activeConnectionKind))
        }, present: { presentation in
            windowContext.dismiss(restoringFocus: false) { playerCoordinator.present(presentation) }
        })
    }

    private func executeCommand(_ id: PlexPaletteCommand.ID) {
        guard store.isPresented, commands.contains(where: { $0.id == id && $0.isEnabled }) else { return }
        let restoresFocus: Bool
        switch id {
        case .navigate, .search, .settings, .closePlayer, .playerInfo, .playerUpNext:
            restoresFocus = false
        default:
            restoresFocus = true
        }
        windowContext.dismiss(restoringFocus: restoresFocus) {
            perform(id)
        }
    }

    private func perform(_ id: PlexPaletteCommand.ID) {
        // Availability may change between choosing a command and dismissing the palette.
        guard commands.contains(where: { $0.id == id && $0.isEnabled }) else { return }
        switch id {
        case .navigate(let section): navigate(section)
        case .search: search?()
        case .refresh: refresh?()
        case .settings: openSettings()
        case .togglePlayback: playerCoordinator.togglePlayback()
        case .previous: playerCoordinator.goPrevious()
        case .next: playerCoordinator.goNext()
        case .skipBackward: playerCoordinator.skipBackward()
        case .skipForward: playerCoordinator.skipForward()
        case .playerInfo: info?()
        case .playerUpNext: upNext?()
        case .closePlayer: closePlayer?()
        }
    }
}
