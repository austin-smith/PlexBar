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

    init() {
        let settingsStore = PlexSettingsStore()
        let sessionStore = PlexSessionStore(settings: settingsStore)
        _settingsStore = State(initialValue: settingsStore)
        _sessionStore = State(initialValue: sessionStore)
        _authStore = State(initialValue: PlexAuthStore(settings: settingsStore, sessionStore: sessionStore))
    }

    var body: some Scene {
        Window("PlexBar Settings", id: AppConstants.settingsWindowID) {
            SettingsView(settingsStore: settingsStore, authStore: authStore, sessionStore: sessionStore)
        }
        .defaultSize(width: 480, height: 300)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContentView(settingsStore: settingsStore, authStore: authStore, sessionStore: sessionStore)
        } label: {
            MenuBarLabelView(streamCount: sessionStore.activeStreamCount)
        }
        .menuBarExtraStyle(.window)
    }
}
