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
    @State private var presentedTooltip: SettingsTooltip?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                generalView
            }

            Tab("About", systemImage: "info.circle", value: .about) {
                aboutView
            }
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
        .task {
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
        case about
    }

    private enum SettingsTooltip: Hashable {
        case connectionRecheck
        case historyRefresh
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
            SettingsAboutView(updateService: updateService)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Authenticated

    private var authenticatedView: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Account")
                            .font(.subheadline.weight(.semibold))

                        accountSummary
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Server")
                            .font(.subheadline.weight(.semibold))

                        serverMenu

                        if let serverStatusMessage {
                            serverStatusBanner(message: serverStatusMessage)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    LabeledContent {
                        Picker("Connection Recheck", selection: connectionRecheckIntervalBinding) {
                            Text("Off").tag(0)
                            Text("5 minutes").tag(300)
                            Text("15 minutes").tag(900)
                            Text("30 minutes").tag(1_800)
                            Text("1 hour").tag(3_600)
                        }
                        .labelsHidden()
                    } label: {
                        settingsTooltipLabel(
                            "Connection Recheck",
                            tooltip: "How often to reevaluate which connection to use for the selected server. A local is preferred over remote or relay when available.",
                            kind: .connectionRecheck
                        )
                    }

                    LabeledContent {
                        Picker("History Refresh", selection: historyPollIntervalBinding) {
                            Text("15 minutes").tag(900)
                            Text("1 hour").tag(3_600)
                            Text("24 hours").tag(86_400)
                        }
                        .labelsHidden()
                    } label: {
                        settingsTooltipLabel(
                            "History Refresh",
                            tooltip: "How often to refresh watch history and library data.",
                            kind: .historyRefresh
                        )
                    }
                }

                Section {
                    openAtLoginControls
                        .padding(.vertical, 2)
                }
            }
            .formStyle(.grouped)
        }
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

    private func settingsTooltipLabel(
        _ title: String,
        tooltip: String,
        kind: SettingsTooltip
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)

            Button {
                presentedTooltip = presentedTooltip == kind ? nil : kind
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: Binding(
                    get: { presentedTooltip == kind },
                    set: { isPresented in
                        if isPresented {
                            presentedTooltip = kind
                        } else if presentedTooltip == kind {
                            presentedTooltip = nil
                        }
                    }
                ),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                settingsTooltipPopover(text: tooltip)
            }
            .accessibilityLabel("\(title) help")
            .accessibilityHint("Shows more information about \(title.lowercased()).")
        }
    }

    private func settingsTooltipPopover(text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 220, alignment: .leading)
            .padding(12)
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
