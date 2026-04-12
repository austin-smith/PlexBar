import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var authStore: PlexAuthStore
    @Bindable var sessionStore: PlexSessionStore

    var body: some View {
        if settingsStore.hasAuthenticatedAccount {
            authenticatedView
        } else {
            unauthenticatedView
        }
    }

    // MARK: - Authenticated

    private var authenticatedView: some View {
        VStack(spacing: 0) {
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
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                }

                Picker("Refresh Interval", selection: pollIntervalBinding) {
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 8) {
                if authStore.isLoadingServers {
                    ProgressView()
                        .controlSize(.small)
                }

                if let statusMessage = authStore.statusMessage {
                    Text(statusLine(statusMessage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let errorMessage = authStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                Spacer()

                Button("Reconnect") {
                    authStore.startSignIn()
                }
                .buttonStyle(.bordered)
                .disabled(authStore.isAuthenticating)

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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 480)
    }

    // MARK: - Unauthenticated

    private var unauthenticatedView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "popcorn.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    Text("Connect Plex")
                        .font(.title2.weight(.semibold))

                    Text("Sign in with your Plex account to connect PlexBar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Sign In With Plex") {
                    authStore.startSignIn()
                }
                .buttonStyle(.borderedProminent)
                .disabled(authStore.isAuthenticating)

                if let statusMessage = authStore.statusMessage {
                    Text(statusLine(statusMessage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = authStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(width: 400, height: 280)
    }

    // MARK: - Helpers

    private var selectedServerBinding: Binding<String> {
        Binding(
            get: { settingsStore.selectedServerIdentifier ?? "" },
            set: { authStore.selectServer(withID: $0) }
        )
    }

    private var pollIntervalBinding: Binding<Int> {
        Binding(
            get: { settingsStore.pollIntervalSeconds },
            set: { newValue in
                guard settingsStore.pollIntervalSeconds != newValue else {
                    return
                }

                settingsStore.pollIntervalSeconds = newValue
                sessionStore.restartPolling()
            }
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
