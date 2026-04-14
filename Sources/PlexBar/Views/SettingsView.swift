import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var authStore: PlexAuthStore
    @Bindable var previewStore: PlexServerPreviewStore
    @Bindable var sessionStore: PlexSessionStore
    @Bindable var historyStore: PlexHistoryStore
    @State private var isShowingServerList = false
    @State private var selectedTab = Tab.general

    var body: some View {
        TabView(selection: $selectedTab) {
            generalView
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(Tab.general)

            aboutView
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(Tab.about)
        }
        .task(id: availableServerIDsKey) {
            previewStore.reconcileServers(authStore.availableServers)

            if let selectedServer {
                previewStore.loadPreviewsIfNeeded(
                    for: [selectedServer],
                    clientIdentifier: settingsStore.clientIdentifier
                )
            }

            if isShowingServerList {
                previewStore.loadPreviewsIfNeeded(
                    for: authStore.availableServers,
                    clientIdentifier: settingsStore.clientIdentifier
                )
            }
        }
        .onChange(of: isShowingServerList) { _, isShowingServerList in
            guard isShowingServerList else {
                return
            }

            previewStore.reconcileServers(authStore.availableServers)
            previewStore.refreshPreviews(
                for: authStore.availableServers,
                clientIdentifier: settingsStore.clientIdentifier
            )
        }
    }

    private enum Tab: Hashable {
        case general
        case about
    }

    private var generalView: some View {
        Group {
            if settingsStore.hasAuthenticatedAccount {
                authenticatedView
            } else {
                unauthenticatedView
            }
        }
    }

    private var aboutView: some View {
        ScrollView {
            SettingsAboutView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    Picker("Active Streams Refresh", selection: pollIntervalBinding) {
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }

                    Picker("History Refresh", selection: historyPollIntervalBinding) {
                        Text("15 minutes").tag(900)
                        Text("1 hour").tag(3_600)
                        Text("24 hours").tag(86_400)
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
                        previewStore.reconcileServers(authStore.availableServers)
                        previewStore.refreshPreviews(
                            for: authStore.availableServers,
                            clientIdentifier: settingsStore.clientIdentifier
                        )
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
        VStack(spacing: 24) {
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
        .frame(width: 480, height: 280)
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

    private var historyPollIntervalBinding: Binding<Int> {
        Binding(
            get: { settingsStore.historyPollIntervalSeconds },
            set: { newValue in
                guard settingsStore.historyPollIntervalSeconds != newValue else {
                    return
                }

                settingsStore.historyPollIntervalSeconds = newValue
                historyStore.restartPolling()
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
                HStack(spacing: 8) {
                    Text(selectedServer?.name ?? settingsStore.selectedServerName ?? "Choose a Server")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let selectedServer {
                        connectionBadge(for: selectedServer)
                    }
                }

                Text(selectedServerSubtitle)
                    .font(.footnote)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if settingsStore.selectedServerIdentifier != nil {
                HStack(spacing: 2) {
                    PosterStackView(
                        state: selectedServerPreviewState,
                        serverURL: selectedServer?.selectedURL ?? settingsStore.normalizedServerURL,
                        token: selectedServer?.accessToken ?? settingsStore.trimmedServerToken,
                        clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                        posterWidth: 36,
                        posterHeight: 54,
                        overlap: 15,
                        cornerRadius: 8
                    )

                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, -1)
                }
            } else {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
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
            LazyVStack(alignment: .leading, spacing: 10) {
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
            .padding(10)
        }
        .frame(minWidth: 380, idealWidth: 380, maxWidth: 380, minHeight: 120, idealHeight: 120, maxHeight: 320)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func serverListRow(for server: PlexServerResource) -> some View {
        let isSelected = settingsStore.selectedServerIdentifier == server.id
        let posterSlotWidth: CGFloat = 103

        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                    HStack(spacing: 8) {
                        Text(server.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        connectionBadge(for: server)
                    }
                }

                Text(serverSubtitle(for: server))
                    .font(.footnote)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, posterSlotWidth + 12)

            PosterStackView(
                state: previewStore.state(for: server.id),
                serverURL: server.selectedURL,
                token: server.accessToken,
                clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                posterWidth: 46,
                posterHeight: 68,
                overlap: 19,
                cornerRadius: 9
            )
            .frame(width: posterSlotWidth, alignment: .trailing)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 14)
        .background(rowBackground(isSelected: isSelected))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.32) : Color.white.opacity(0.06))
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var selectedServerSubtitle: String {
        guard let selectedServer else {
            return "Plex Media Server"
        }

        return serverSubtitle(for: selectedServer)
    }

    private var selectedServerPreviewState: PlexServerPreviewState {
        previewStore.state(for: selectedServer?.id ?? settingsStore.selectedServerIdentifier)
    }

    private var availableServerIDsKey: String {
        authStore.availableServers.map(\.id).sorted().joined(separator: "|")
    }

    private func serverSubtitle(for server: PlexServerResource) -> String {
        server.displayProductVersion ?? "Plex Media Server"
    }

    @ViewBuilder
    private func connectionBadge(for server: PlexServerResource) -> some View {
        Text(server.connectionSummary)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
    }

    private func rowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                isSelected
                    ? LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.18),
                            Color.accentColor.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.02),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
            )
    }
}
