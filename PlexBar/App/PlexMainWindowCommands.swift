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
}

struct PlexMainWindowCommands: Commands {
    @FocusedValue(\.plexRefreshCommand) private var refreshCommand
    @FocusedValue(\.plexSearchCommand) private var searchCommand
    @FocusedValue(\.plexPlayerInfoCommand) private var playerInfoCommand
    @FocusedValue(\.plexPlayerUpNextCommand) private var playerUpNextCommand

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()

            Button(playerInfoCommand?.title ?? "Show Info") {
                playerInfoCommand?()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(playerInfoCommand?.isEnabled != true)

            Button(playerUpNextCommand?.title ?? "Show Up Next") {
                playerUpNextCommand?()
            }
            .disabled(playerUpNextCommand?.isEnabled != true)

            Divider()

            Button(searchCommand?.title ?? "Search") {
                searchCommand?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(searchCommand?.isEnabled != true)

            Button(refreshCommand?.title ?? "Refresh") {
                refreshCommand?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(refreshCommand?.isEnabled != true)
        }
    }
}
