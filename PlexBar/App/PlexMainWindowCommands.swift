import PlexClientKit
import SwiftUI

struct PlexFocusedCommandAction {
    let title: String
    let isEnabled: Bool
    let perform: () -> Void

    init(
        title: String,
        isEnabled: Bool = true,
        perform: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.perform = perform
    }

    func callAsFunction() {
        perform()
    }
}

extension FocusedValues {
    @Entry var plexRefreshCommand: PlexFocusedCommandAction?
    @Entry var plexSearchCommand: PlexFocusedCommandAction?
    @Entry var plexPlayerInfoCommand: PlexFocusedCommandAction?
    @Entry var plexPlayerUpNextCommand: PlexFocusedCommandAction?
    @Entry var plexPlayerCloseCommand: PlexFocusedCommandAction?
}

struct PlexMainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Bindable var paletteStore: PlexCommandPaletteStore
    @FocusedValue(\.plexRefreshCommand) private var refreshCommand
    @FocusedValue(\.plexSearchCommand) private var searchCommand
    @FocusedValue(\.plexPlayerInfoCommand) private var playerInfoCommand
    @FocusedValue(\.plexPlayerUpNextCommand) private var playerUpNextCommand

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()

            Button("Search Library and Commands…") {
                if paletteStore.isPresented {
                    paletteStore.dismiss()
                } else {
                    paletteStore.request()
                    if paletteStore.isPresentationRequested {
                        openWindow(id: PlexMainNavigationStore.windowID)
                    }
                }
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button(playerInfoCommand?.title ?? "Show Info") {
                playerInfoCommand?()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(paletteStore.isPresented || playerInfoCommand?.isEnabled != true)

            Button(playerUpNextCommand?.title ?? "Show Up Next") {
                playerUpNextCommand?()
            }
            .disabled(paletteStore.isPresented || playerUpNextCommand?.isEnabled != true)

            Divider()

            Button(searchCommand?.title ?? "Search") {
                searchCommand?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(paletteStore.isPresented || searchCommand?.isEnabled != true)

            Button(refreshCommand?.title ?? "Refresh") {
                refreshCommand?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(paletteStore.isPresented || refreshCommand?.isEnabled != true)
        }
    }
}
