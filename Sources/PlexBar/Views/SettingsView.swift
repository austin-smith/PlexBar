import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var authStore: PlexAuthStore
    @Bindable var sessionStore: PlexSessionStore
    @State private var isShowingServerList = false

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
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Server")
                            .font(.subheadline.weight(.semibold))

                        serverMenu
                    }
                    .padding(.vertical, 2)
                }

                Section {
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
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 8) {
                if authStore.isLoadingServers {
                    ProgressView()
                        .controlSize(.small)
                }

                if let errorMessage = authStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                Spacer()

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

    private var selectedServer: PlexServerResource? {
        guard let selectedServerIdentifier = settingsStore.selectedServerIdentifier else {
            return nil
        }

        return authStore.availableServers.first(where: { $0.id == selectedServerIdentifier })
    }

    private var serverMenu: some View {
        Button {
            isShowingServerList.toggle()
        } label: {
            serverMenuLabel
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingServerList, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            serverListPopover
        }
    }

    private var serverMenuLabel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedServer?.name ?? settingsStore.selectedServerName ?? "Choose a Server")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(selectedServerSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var serverListPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if authStore.availableServers.isEmpty {
                    Text("No servers available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    ForEach(authStore.availableServers) { server in
                        Button {
                            authStore.selectServer(withID: server.id)
                            isShowingServerList = false
                        } label: {
                            serverListRow(for: server)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(8)
        }
        .frame(minWidth: 320, idealWidth: 320, maxWidth: 320, minHeight: 220, idealHeight: 220, maxHeight: 280)
    }

    @ViewBuilder
    private func serverListRow(for server: PlexServerResource) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if settingsStore.selectedServerIdentifier == server.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .foregroundStyle(.primary)

                Text(server.displayProductVersion ?? "Plex Media Server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground(isSelected: settingsStore.selectedServerIdentifier == server.id))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var selectedServerSubtitle: String {
        selectedServer?.displayProductVersion ?? "Plex Media Server"
    }

    private func rowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
    }
}
