import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // This is intentionally a menu-bar-first app without a Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct PlexBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settingsStore: PlexSettingsStore
    @State private var authStore: PlexAuthStore
    @State private var sessionStore: PlexSessionStore
    @State private var historyStore: PlexHistoryStore
    @State private var libraryStore: PlexLibraryStore

    init() {
        let settingsStore = PlexSettingsStore()
        let sessionStore = PlexSessionStore(settings: settingsStore)
        let libraryStore = PlexLibraryStore(settings: settingsStore)
        let historyStore = PlexHistoryStore(settings: settingsStore, libraryStore: libraryStore)
        _settingsStore = State(initialValue: settingsStore)
        _sessionStore = State(initialValue: sessionStore)
        _historyStore = State(initialValue: historyStore)
        _libraryStore = State(initialValue: libraryStore)
        _authStore = State(initialValue: PlexAuthStore(
            settings: settingsStore,
            sessionStore: sessionStore,
            historyStore: historyStore,
            libraryStore: libraryStore
        ))
    }

    var body: some Scene {
        Window("PlexBar Settings", id: AppConstants.settingsWindowID) {
            SettingsView(
                settingsStore: settingsStore,
                authStore: authStore,
                sessionStore: sessionStore,
                historyStore: historyStore
            )
        }
        .defaultSize(width: 480, height: 300)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContentView(
                settingsStore: settingsStore,
                authStore: authStore,
                sessionStore: sessionStore,
                historyStore: historyStore,
                libraryStore: libraryStore
            )
        } label: {
            MenuBarLabelView(streamCount: sessionStore.activeStreamCount)
        }
        .menuBarExtraStyle(.window)
    }
}
