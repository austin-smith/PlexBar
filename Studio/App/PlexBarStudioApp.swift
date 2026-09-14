import SwiftUI

@main
struct PlexBarStudioApp: App {
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var appDelegate
    @State private var store = StudioStore()

    var body: some Scene {
        Window("PlexBar Studio", id: "studio") {
            StudioWorkspaceView(store: store)
                .onAppear { appDelegate.store = store }
                .frame(minWidth: 1080, minHeight: 720)
                .tint(.orange)
        }
        .defaultSize(width: 1440, height: 920)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            InspectorCommands()
        }

        Settings {
            StudioSettingsView(store: store)
                .tint(.orange)
        }
        .windowResizability(.contentSize)
    }
}
