import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var authStore: PlexAuthStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(titleText)
                    .font(.title2.weight(.semibold))

                Text(descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Button(settingsStore.hasAuthenticatedAccount ? "Reconnect Plex" : "Sign In With Plex") {
                    authStore.startSignIn()
                }
                .buttonStyle(.borderedProminent)
                .disabled(authStore.isAuthenticating)

                if settingsStore.hasAuthenticatedAccount {
                    HStack(spacing: 10) {
                        Button("Refresh Servers") {
                            Task {
                                await authStore.refreshServers(autoSelectStoredServer: true)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(authStore.isAuthenticating || authStore.isLoadingServers)

                        Button("Sign Out") {
                            authStore.signOut()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let statusMessage = authStore.statusMessage {
                    Text(statusLine(statusMessage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage = authStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if settingsStore.hasAuthenticatedAccount {
                Form {
                    Picker("Server", selection: selectedServerBinding) {
                        if authStore.availableServers.isEmpty {
                            Text("No servers available").tag("")
                        } else {
                            ForEach(authStore.availableServers) { server in
                                Text(server.name).tag(server.id)
                            }
                        }
                    }

                    LabeledContent("Connected URL") {
                        Text(settingsStore.serverURLString.nilIfBlank ?? "None")
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .formStyle(.grouped)

                if authStore.isLoadingServers {
                    ProgressView("Loading Plex servers…")
                        .controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(width: settingsStore.hasAuthenticatedAccount ? 500 : 420, alignment: .leading)
    }

    private var titleText: String {
        settingsStore.hasAuthenticatedAccount ? "Choose Server" : "Connect Plex"
    }

    private var descriptionText: String {
        if settingsStore.hasAuthenticatedAccount {
            return "Choose the Plex Media Server PlexBar should watch for active streams."
        }

        return "Sign in with your Plex account to connect PlexBar."
    }

    private var selectedServerBinding: Binding<String> {
        Binding(
            get: { settingsStore.selectedServerIdentifier ?? "" },
            set: { authStore.selectServer(withID: $0) }
        )
    }

    private func statusLine(_ message: String) -> String {
        if let remainingSeconds = authStore.remainingSeconds {
            let minutes = remainingSeconds / 60
            let seconds = remainingSeconds % 60
            return "\(message) \(minutes):" + String(format: "%02d", seconds)
        }

        return message
    }
}
