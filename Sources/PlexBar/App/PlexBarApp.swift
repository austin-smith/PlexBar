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
    @State private var connectionStore: PlexConnectionStore
    @State private var authStore: PlexAuthStore
    @State private var sessionStore: PlexSessionStore
    @State private var historyStore: PlexHistoryStore
    @State private var libraryStore: PlexLibraryStore
    @State private var serverPreviewStore: PlexServerPreviewStore
    private let updateService: PlexUpdateService

    init() {
        let settingsStore = PlexSettingsStore()
        let resolver = PlexConnectionResolver()
        let connectionStore = PlexConnectionStore(settings: settingsStore, resolver: resolver)
        let sessionStore = PlexSessionStore(connectionStore: connectionStore)
        let libraryStore = PlexLibraryStore(connectionStore: connectionStore)
        let historyStore = PlexHistoryStore(connectionStore: connectionStore, libraryStore: libraryStore)
        let serverPreviewStore = PlexServerPreviewStore(resolver: resolver)
        _settingsStore = State(initialValue: settingsStore)
        _connectionStore = State(initialValue: connectionStore)
        _sessionStore = State(initialValue: sessionStore)
        _historyStore = State(initialValue: historyStore)
        _libraryStore = State(initialValue: libraryStore)
        _serverPreviewStore = State(initialValue: serverPreviewStore)
        _authStore = State(initialValue: PlexAuthStore(
            settings: settingsStore,
            connectionStore: connectionStore,
            sessionStore: sessionStore,
            historyStore: historyStore,
            libraryStore: libraryStore
        ))
        updateService = PlexUpdateService()
    }

    var body: some Scene {
        Settings {
            SettingsView(
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                authStore: authStore,
                previewStore: serverPreviewStore,
                sessionStore: sessionStore,
                historyStore: historyStore,
                updateService: updateService
            )
        }
        .defaultSize(width: 480, height: 520)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContentView(
                settingsStore: settingsStore,
                connectionStore: connectionStore,
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
