import SwiftUI

struct PlexAdvancedSettingsView: View {
    @Bindable var settingsStore: PlexSettingsStore
    @Binding var connectionRecheckInterval: Int
    @Binding var historyPollInterval: Int

    var body: some View {
        Form {
            Section {
                Picker(selection: $connectionRecheckInterval) {
                    Text("Off").tag(0)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1_800)
                    Text("1 hour").tag(3_600)
                } label: {
                    SettingsControlLabel(
                        title: "Connection Recheck",
                        detail: "Check for a better connection to the selected server."
                    )
                }
            } header: {
                Text("Server Connection")
            } footer: {
                Text("Local connections are preferred over remote or relay connections.")
            }

            Section {
                Picker(selection: $historyPollInterval) {
                    Text("15 minutes").tag(900)
                    Text("1 hour").tag(3_600)
                    Text("24 hours").tag(86_400)
                } label: {
                    SettingsControlLabel(
                        title: "Refresh Interval",
                        detail: "Update watch history and library data in the background."
                    )
                }
            } header: {
                Text("Background Refresh")
            }

            Section {
                Toggle(isOn: $settingsStore.allowsDirectPlay) {
                    SettingsControlLabel(
                        title: "Allow Direct Play",
                        detail: "Play the original media file without server conversion."
                    )
                }
                Toggle(isOn: $settingsStore.allowsDirectStream) {
                    SettingsControlLabel(
                        title: "Allow Direct Stream",
                        detail: "Let Plex repackage media without converting compatible video or audio tracks."
                    )
                }
                Toggle(isOn: $settingsStore.forceDirectPlay) {
                    SettingsControlLabel(
                        title: "Force Direct Play",
                        detail: "For supported files, bypass the server’s playback decision. Requires Allow Direct Play."
                    )
                }
                .disabled(!settingsStore.allowsDirectPlay)
            } header: {
                Text("Streaming")
            } footer: {
                Text("Disabling Direct Play or Direct Stream can require Plex to convert media on your server.")
            }
        }
        .formStyle(.grouped)
    }
}
