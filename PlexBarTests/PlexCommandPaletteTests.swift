import PlexClientKit
import AppKit
import PlexModels
import Testing
@testable import PlexBar

@MainActor
struct PlexCommandPaletteTests {
    @Test func matchingUsesExplicitKeywordsAndStableRanking() {
        let commands: [PlexPaletteCommand] = [
            .init(id: .navigate(.home), title: "Open Home", systemImage: "house", group: .navigation),
            .init(id: .navigate(.library("1")), title: "Open Cinéma", systemImage: "film", group: .libraries,
                  keywords: ["cinema", "movies"]),
            .init(id: .settings, title: "Open Settings", systemImage: "gearshape", group: .app,
                  keywords: ["preferences"]),
            .init(id: .search, title: "Search All Libraries", systemImage: "magnifyingglass", group: .currentView)
        ]
        #expect(PlexPaletteCommand.matching(commands, query: "  CINEMA  ").map(\.id) == [.navigate(.library("1"))])
        #expect(PlexPaletteCommand.matching(commands, query: "preferences").map(\.id) == [.settings])
        #expect(PlexPaletteCommand.matching(commands, query: "cinema open").map(\.id) == [.navigate(.library("1"))])
        #expect(PlexPaletteCommand.matching(commands, query: "open").map(\.id) == Array(commands.prefix(3)).map(\.id))
        #expect(PlexPaletteCommand.matching(commands, query: " \n ") == commands)
        #expect(PlexPaletteCommand.matching(commands, query: "cinmea").isEmpty)

        let ranked = [commands[0], PlexPaletteCommand(
            id: .refresh, title: "Home", systemImage: "house", group: .currentView
        )]
        #expect(PlexPaletteCommand.matching(ranked, query: "home").map(\.id) == [.refresh, .navigate(.home)])
    }

    @Test func selectionSkipsDisabledCommandsAndRemainsStableAcrossUpdates() throws {
        let store = PlexCommandPaletteStore()
        var commands = navigationCommands()
        store.updateCommands(commands)
        store.present()
        #expect(store.selectedID == .command(.navigate(.home)))
        store.moveSelection(by: 1)
        #expect(store.selectedID == .command(.navigate(.downloads)))
        store.moveSelection(by: 1)
        #expect(store.selectedID == .command(.settings))
        store.moveSelection(by: 1)
        #expect(store.selectedID == .command(.settings))
        store.moveSelection(by: -1)
        #expect(store.selectedID == .command(.navigate(.downloads)))

        commands[0] = .init(id: .navigate(.home), title: "Go Home", systemImage: "house", group: .navigation)
        store.updateCommands(commands)
        #expect(store.selectedID == .command(.navigate(.downloads)))
        store.query = "settings"
        #expect(store.selectedID == .command(.settings))
        store.query = "unmatched"
        #expect(store.selectedCommand == nil)
        store.moveSelection(by: 1)
        #expect(store.selectedCommand == nil)
        store.query = "activity"
        #expect(store.results.count == 1)
        #expect(store.selectedCommand == nil)

        store.dismiss()
        store.present()
        #expect(store.query.isEmpty)
        #expect(store.selectedID == .command(.navigate(.home)))
        commands[0].unavailableReason = "Unavailable"
        store.updateCommands(commands)
        #expect(store.selectedID == .command(.navigate(.downloads)))
    }

    @Test func offlineCatalogKeepsDownloadsAndSettingsAvailable() {
        let commands = catalog(player: PlexPlayerCoordinator(), hasConfiguration: false)
        #expect(commands.first { $0.id == .navigate(.downloads) }?.isEnabled == true)
        #expect(commands.first { $0.id == .navigate(.home) }?.isEnabled == true)
        #expect(commands.first { $0.id == .settings }?.isEnabled == true)
        #expect(commands.first { $0.id == .navigate(.activity) }?.isEnabled == false)
        #expect(!commands.contains { $0.id == .togglePlayback })
    }

    @Test func openingASectionReturnsToItsRootWithoutResettingOtherSections() throws {
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: Data(
            #"{"ratingKey":"42","title":"Palette Test","type":"movie","Media":[]}"#.utf8
        ))
        let route = PlexNavigationRoute.media(PlexMediaRoute(item: item))
        let navigation = PlexMainNavigationStore()
        navigation.homeNavigationPath = [route]
        navigation.historyNavigationPath = [route]
        navigation.openRoot(.home)
        #expect(navigation.selection == .home)
        #expect(navigation.homeNavigationPath.isEmpty)
        #expect(navigation.historyNavigationPath == [route])
        navigation.openRoot(.history)
        #expect(navigation.selection == .history)
        #expect(navigation.historyNavigationPath.isEmpty)
    }

    @Test func playbackCatalogUsesCapabilitiesAndExplicitStopNavigation() throws {
        let player = PlexPlayerCoordinator()
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: Data(
            #"{"ratingKey":"42","title":"Palette Test","type":"movie","Media":[]}"#.utf8
        ))
        player.presentation = PlexPlaybackPresentation(
            item: item,
            plan: PlexPlaybackPlan(
                url: URL(fileURLWithPath: "/tmp/palette-test.mp4"), method: .directPlay,
                mediaKind: .video, sessionIdentifier: "palette-test", ratingKey: "42",
                duration: 120, startTime: 0, source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
                usesServerMediaSelection: false
            ), queue: nil, videoQuality: .original
        )
        player.installTransport(status: .playing, toggle: {}, stop: {})
        player.updateTransport(status: .playing)
        player.installSeeking(canSeek: true) { _ in }
        var commands = catalog(player: player)
        #expect(commands.first { $0.id == .togglePlayback }?.title == "Pause Playback")
        #expect(commands.contains { $0.id == .skipForward })
        #expect(!commands.contains { $0.id == .next })
        #expect(!commands.contains { $0.id == .search })
        #expect(commands.first { $0.id == .navigate(.downloads) }?.isEnabled == false)
        #expect(commands.first { $0.id == .closePlayer }?.title == "Stop Playback and Return to Library")

        player.updateTransport(status: .paused)
        player.updateSeeking(canSeek: false)
        commands = catalog(player: player)
        #expect(commands.first { $0.id == .togglePlayback }?.title == "Resume Playback")
        #expect(!commands.contains { $0.id == .skipForward })
    }

    @Test func requestsWaitForTheMainWindowAndCancelWhenItCloses() {
        let store = PlexCommandPaletteStore()
        let context = PlexCommandPaletteWindowContext()
        let window = PaletteTestWindow()
        defer { context.detach(); window.orderOut(nil) }
        context.attach(to: window, store: store)
        store.request()
        #expect(store.isPresentationRequested)
        #expect(!store.isPresented)
        window.hasKeyFocus = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(store.isPresented)
        #expect(!store.isPresentationRequested)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(!store.isPresented)
        #expect(!store.isPresentationRequested)
    }

    @Test func aSheetBlocksPalettePresentation() {
        let store = PlexCommandPaletteStore()
        let context = PlexCommandPaletteWindowContext()
        let window = PaletteTestWindow()
        window.testSheet = NSWindow()
        defer { context.detach(); window.orderOut(nil) }
        context.attach(to: window, store: store)
        store.request()
        #expect(!store.isPresented)
        #expect(!store.isPresentationRequested)
    }

    private func navigationCommands() -> [PlexPaletteCommand] {
        [
            .init(id: .navigate(.home), title: "Open Home", systemImage: "house", group: .navigation),
            .init(id: .navigate(.activity), title: "Open Activity", systemImage: "play.rectangle", group: .navigation,
                  unavailableReason: "Connect to a server"),
            .init(id: .navigate(.downloads), title: "Open Downloads", systemImage: "arrow.down.circle", group: .navigation),
            .init(id: .settings, title: "Open Settings", systemImage: "gearshape", group: .app)
        ]
    }

    private func catalog(player: PlexPlayerCoordinator, hasConfiguration: Bool = true) -> [PlexPaletteCommand] {
        PlexCommandPaletteCatalog.commands(
            libraries: [], hasConfiguration: hasConfiguration, player: player,
            search: .init(title: "Search All Libraries", isEnabled: hasConfiguration, perform: {}),
            refresh: .init(title: "Refresh Downloads", perform: {}), info: nil, upNext: nil,
            closePlayer: .init(title: "Stop Playback and Return to Library", perform: {})
        )
    }
}

@MainActor
private final class PaletteTestWindow: NSWindow {
    var hasKeyFocus = false
    var testSheet: NSWindow?
    override var isKeyWindow: Bool { hasKeyFocus }
    override var attachedSheet: NSWindow? { testSheet }
}
