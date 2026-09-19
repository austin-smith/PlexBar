import PlexClientKit
import PlexModels
import SwiftUI

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var authStore: PlexAuthStore
    @Bindable var previewStore: PlexServerPreviewStore
    @Bindable var sessionStore: PlexSessionStore
    @Bindable var historyStore: PlexHistoryStore
    let updateService: PlexUpdateService
    @State private var isShowingServerList = false
    @State private var selectedTab = SettingsTab.general

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                generalView
            }

            Tab("Playback", systemImage: "play.circle", value: .playback) {
                PlexPlaybackSettingsView(settingsStore: settingsStore)
            }

            Tab("Downloads", systemImage: "arrow.down.circle", value: .downloads) {
                PlexDownloadSettingsView(settingsStore: settingsStore)
            }

            Tab("Advanced", systemImage: "slider.horizontal.3", value: .advanced) {
                PlexAdvancedSettingsView(
                    settingsStore: settingsStore,
                    connectionRecheckInterval: connectionRecheckIntervalBinding,
                    historyPollInterval: historyPollIntervalBinding
                )
            }

            Tab("About", systemImage: "info.circle", value: .about) {
                aboutView
            }
        }
        .frame(width: 520)
        .frame(minHeight: 520)
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
        .task {
            await settingsStore.loadCredentials()
            await authStore.credentialsDidLoad()
            settingsStore.refreshOpenAtLoginStatus()
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
        .onChange(of: scenePhase) { _, scenePhase in
            guard scenePhase == .active else {
                return
            }

            settingsStore.refreshOpenAtLoginStatus()
        }
    }

    private enum SettingsTab: Hashable {
        case general
        case playback
        case downloads
        case advanced
        case about
    }

    private var generalView: some View {
        Form {
            Section("Account") {
                accountControls
            }

            if settingsStore.hasLoadedCredentials && settingsStore.hasAuthenticatedAccount {
                Section("Server") {
                    serverMenu

                    if let serverStatusMessage {
                        serverStatusBanner(message: serverStatusMessage)
                    }
                }
            }

            Section("App") {
                openAtLoginControls
            }

            Section("Library") {
                Picker("Hide Episode Spoilers", selection: $settingsStore.episodeSpoilerPolicy) {
                    ForEach(PlexEpisodeSpoilerPolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var accountControls: some View {
        if !settingsStore.hasLoadedCredentials {
            if let errorMessage = settingsStore.credentialLoadingErrorMessage,
               !settingsStore.isLoadingCredentials {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Couldn’t Access Keychain", systemImage: "key.slash")
                        .font(.headline)
                    serverStatusBanner(message: errorMessage)
                    Button("Try Again") {
                        Task {
                            await settingsStore.loadCredentials()
                            await authStore.credentialsDidLoad()
                        }
                    }
                }
            } else {
                ProgressView("Loading Account…")
                    .controlSize(.small)
            }
        } else if settingsStore.hasAuthenticatedAccount {
            if let credentialErrorMessage = settingsStore.credentialPersistenceErrorMessage {
                serverStatusBanner(message: credentialErrorMessage)
            }
            accountSummary
                .padding(.vertical, 2)
        } else {
            signInControls
        }
    }

    private var signInControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                SettingsControlLabel(
                    title: "Connect to Plex",
                    detail: "Sign in to browse your libraries and stream media."
                )
                Spacer(minLength: 0)

                if authStore.canCancelSignIn {
                    Button("Cancel", role: .cancel) {
                        authStore.cancelSignIn()
                    }
                } else if !authStore.isAuthenticating {
                    Button("Sign In") {
                        authStore.startSignIn()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let progressMessage = authStore.signInProgressMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = authStore.errorMessage
                ?? settingsStore.credentialPersistenceErrorMessage {
                serverStatusBanner(message: errorMessage)
            }
        }
        .padding(.vertical, 2)
    }

    private var aboutView: some View {
        ScrollView {
            SettingsAboutView(updateService: updateService)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Helpers

    private var selectedServerBinding: Binding<String> {
        Binding(
            get: { settingsStore.selectedServerIdentifier ?? "" },
            set: { authStore.selectServer(withID: $0) }
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

    private var connectionRecheckIntervalBinding: Binding<Int> {
        Binding(
            get: { settingsStore.connectionRecheckIntervalSeconds },
            set: { newValue in
                guard settingsStore.connectionRecheckIntervalSeconds != newValue else {
                    return
                }

                settingsStore.connectionRecheckIntervalSeconds = newValue
                sessionStore.restartConnectionRecheckTask()
            }
        )
    }

    private var openAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.opensAtLogin },
            set: { newValue in
                guard settingsStore.opensAtLogin != newValue else {
                    return
                }

                settingsStore.setOpenAtLogin(newValue)
            }
        )
    }

    private var selectedServer: PlexServerResource? {
        guard let selectedServerIdentifier = settingsStore.selectedServerIdentifier else {
            return nil
        }

        return authStore.availableServers.first(where: { $0.id == selectedServerIdentifier })
    }

    @ViewBuilder
    private var accountSummary: some View {
        if let accountErrorMessage = authStore.accountErrorMessage {
            VStack(alignment: .leading, spacing: 10) {
                serverStatusBanner(message: accountErrorMessage)

                HStack {
                    Spacer(minLength: 0)
                    signOutButton
                }
            }
        } else {
            HStack(spacing: 10) {
                accountAvatar

                VStack(alignment: .leading, spacing: 4) {
                    if let authenticatedUser = authStore.authenticatedUser {
                        Text(authenticatedUser.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let displayEmail = authenticatedUser.displayEmail {
                            Text(displayEmail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }

                        if let displayUsername = authenticatedUser.displayUsername {
                            Text(displayUsername)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else if authStore.isLoadingAuthenticatedUser {
                        Text("Loading account…")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Fetching Plex account details")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(settingsStore.selectedServerName ?? "Plex account connected")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("Account details will appear once they finish loading.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 12)

                signOutButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44, alignment: .leading)
        }
    }

    private var openAtLoginControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Open at Login", isOn: openAtLoginBinding)

            if settingsStore.openAtLoginRequiresApproval {
                settingsInfoBanner(message: "Finish enabling PlexBar in Login Items in System Settings.")

                Button("Open System Settings") {
                    settingsStore.openLoginItemsSystemSettings()
                }
                .buttonStyle(.bordered)
            }

            if let openAtLoginErrorMessage = settingsStore.openAtLoginErrorMessage {
                serverStatusBanner(message: openAtLoginErrorMessage)
            }
        }
    }

    @ViewBuilder
    private var accountAvatar: some View {
        if let authenticatedUser = authStore.authenticatedUser {
            PlexAvatarView(
                thumb: authenticatedUser.thumb,
                serverURL: nil,
                serverToken: "",
                userToken: settingsStore.trimmedUserToken,
                clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                size: 44
            )
        } else {
            ZStack {
                Circle()
                    .fill(.quaternary)

                if authStore.isLoadingAuthenticatedUser {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 44, height: 44)
        }
    }

    private var signOutButton: some View {
        Button("Sign Out") {
            authStore.signOut()
        }
        .buttonStyle(.bordered)
    }

    private var serverMenu: some View {
        Button {
            isShowingServerList.toggle()
        } label: {
            serverMenuLabel
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

                    if settingsStore.selectedServerIdentifier != nil {
                        activeConnectionBadge
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
                        serverURL: connectionStore.resolvedServerURL,
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
    }

    private func refreshServers() {
        Task {
            await authStore.refreshServers(autoSelectStoredServer: true)
            previewStore.reconcileServers(authStore.availableServers)
            previewStore.refreshPreviews(
                for: authStore.availableServers,
                clientIdentifier: settingsStore.clientIdentifier
            )
        }
    }

    private var serverListPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Servers")
                    .font(.headline)

                Spacer()

                if authStore.isLoadingServers {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Refresh Servers") {
                        refreshServers()
                    }
                    .buttonStyle(.bordered)
                    .disabled(authStore.isAuthenticating || authStore.isLoadingServers)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

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
        }
        .frame(minWidth: 380, idealWidth: 380, maxWidth: 380, minHeight: 180, idealHeight: 220, maxHeight: 360)
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

                        if isSelected {
                            activeConnectionBadge
                        }
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
                serverURL: previewStore.state(for: server.id).serverURL,
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
        guard let version = server.displayProductVersion else {
            return "Plex Media Server"
        }

        return "v\(version)"
    }

    @ViewBuilder
    private var activeConnectionBadge: some View {
        Text(activeConnectionBadgeLabel)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
    }

    private var activeConnectionBadgeLabel: String {
        if connectionStore.isResolving {
            return "Resolving…"
        }

        if connectionStore.errorMessage != nil {
            return "Unavailable"
        }

        return connectionStore.activeConnectionKind?.displayName ?? "Unavailable"
    }

    private var serverStatusMessage: String? {
        if let connectionErrorMessage = connectionStore.errorMessage {
            return connectionErrorMessage
        }

        return authStore.errorMessage
    }

    @ViewBuilder
    private func serverStatusBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.22))
        }
    }

    @ViewBuilder
    private func settingsInfoBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.22))
        }
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
