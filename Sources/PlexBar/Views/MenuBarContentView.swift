import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var authStore: PlexAuthStore
    @Bindable var sessionStore: PlexSessionStore
    @Bindable var historyStore: PlexHistoryStore
    @Bindable var libraryStore: PlexLibraryStore
    @Environment(\.openSettings) private var openSettingsWindow
    @State private var selectedSection: DashboardSection = .streams
    @State private var streamContentHeight: CGFloat = 0
    @State private var historyContentHeight: CGFloat = 0
    @State private var usersContentHeight: CGFloat = 0
    @State private var libraryContentHeight: CGFloat = 0
    @State private var expandedStreamID: String?
    @State private var terminatePrompt: TerminatePlaybackPrompt?
    @State private var terminateMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionPicker
            header
            content
            footer
        }
        .padding(16)
        .frame(width: 420)
        .animation(.snappy(duration: 0.18), value: terminatePrompt?.id)
        .animation(.snappy(duration: 0.18), value: expandedStreamID)
    }

    private var header: some View {
        switch selectedSection {
        case .streams:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("Active Streams")
                        .font(.headline)

                    Spacer()

                    if sessionStore.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .history:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("Watch History")
                        .font(.headline)

                    Spacer()

                    if historyStore.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .users:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("Users")
                        .font(.headline)

                    Spacer()

                    if historyStore.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .libraries:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("Libraries")
                        .font(.headline)

                    Spacer()

                    if libraryStore.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(DashboardSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.controlTitle, systemImage: section.systemImage)
                        .font(.subheadline.weight(selectedSection == section ? .semibold : .regular))
                        .foregroundStyle(selectedSection == section ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedSection == section ? Color.accentColor.opacity(0.18) : .clear)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.snappy(duration: 0.18), value: selectedSection)
    }

    @ViewBuilder
    private var content: some View {
        if !settingsStore.hasValidConfiguration {
            EmptyStateView(
                icon: "link",
                title: settingsStore.hasAuthenticatedAccount ? "Choose a Server" : "Connect Plex",
                message: settingsStore.hasAuthenticatedAccount
                    ? "PlexBar signed in successfully, but no Plex Media Server is selected yet."
                    : "Sign in with Plex to discover your servers and start watching active streams.",
                actionTitle: "Open Settings"
            ) {
                openSettings()
            }
        } else {
            switch selectedSection {
            case .streams:
                streamsContent
            case .history:
                historyContent
            case .users:
                usersContent
            case .libraries:
                librariesContent
            }

            if let inlineErrorMessage = selectedSection.inlineErrorMessage(
                sessionStore: sessionStore,
                historyStore: historyStore,
                libraryStore: libraryStore
            ) {
                InlineWarningBanner(message: inlineErrorMessage)
            }
        }
    }

    @ViewBuilder
    private var streamsContent: some View {
        if let errorMessage = sessionStore.errorMessage, sessionStore.sessions.isEmpty {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Couldn’t Reach Plex",
                message: errorMessage,
                actionTitle: "Refresh"
            ) {
                refreshAllData()
            }
        } else if sessionStore.sessions.isEmpty {
            EmptyStateView(
                icon: "popcorn",
                title: "No Active Streams",
                message: "Nothing is currently playing on this server."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(sessionStore.sessions) { session in
                        StreamCardView(
                            session: session,
                            sessionStore: sessionStore,
                            onRequestTerminate: presentTerminatePrompt,
                            isShowingTerminatePrompt: terminatePrompt?.id == session.id,
                            terminateMessage: $terminateMessage,
                            onCancelTerminate: dismissTerminatePrompt,
                            onConfirmTerminate: confirmTerminate,
                            serverURL: connectionStore.resolvedServerURL,
                            settingsStore: settingsStore,
                            snapshotDate: sessionStore.lastUpdated,
                            resolvedLocation: sessionStore.resolvedLocation(for: session),
                            isExpanded: expandedStreamID == session.id
                        ) {
                            toggleExpandedStream(session)
                        }
                    }
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: MenuBarContentHeightPreferenceKey.self, value: proxy.size.height)
                    }
                }
            }
            .frame(height: streamListHeight, alignment: .top)
            .onPreferenceChange(MenuBarContentHeightPreferenceKey.self) { newHeight in
                guard abs(streamContentHeight - newHeight) > 0.5 else {
                    return
                }

                streamContentHeight = newHeight
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if let errorMessage = historyStore.errorMessage, historyStore.recentItems.isEmpty {
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: "Couldn’t Load Watch History",
                message: errorMessage,
                actionTitle: "Refresh"
            ) {
                refreshAllData()
            }
        } else if historyStore.recentItems.isEmpty {
            EmptyStateView(
                icon: "clock",
                title: "No Watch History Yet",
                message: "Recent watches and charting will appear here after people finish something on this server."
            )
        } else {
            ScrollView {
                HistoryDashboardView(
                    settingsStore: settingsStore,
                    serverURL: connectionStore.resolvedServerURL,
                    historyStore: historyStore
                )
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: MenuBarContentHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    }
            }
            .frame(height: historyListHeight, alignment: .top)
            .onPreferenceChange(MenuBarContentHeightPreferenceKey.self) { newHeight in
                guard abs(historyContentHeight - newHeight) > 0.5 else {
                    return
                }

                historyContentHeight = newHeight
            }
        }
    }

    @ViewBuilder
    private var usersContent: some View {
        if let errorMessage = historyStore.errorMessage, historyStore.recentItems.isEmpty {
            EmptyStateView(
                icon: "person.2",
                title: "Couldn’t Load Users",
                message: errorMessage,
                actionTitle: "Refresh"
            ) {
                refreshAllData()
            }
        } else if historyStore.recentItems.isEmpty {
            EmptyStateView(
                icon: "person.2",
                title: "No User Activity Yet",
                message: "User activity will appear here after people watch something on this server."
            )
        } else {
            ScrollView {
                UsersDashboardView(
                    settingsStore: settingsStore,
                    serverURL: connectionStore.resolvedServerURL,
                    historyStore: historyStore
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: MenuBarContentHeightPreferenceKey.self, value: proxy.size.height)
                    }
                }
            }
            .frame(height: usersListHeight, alignment: .top)
            .onPreferenceChange(MenuBarContentHeightPreferenceKey.self) { newHeight in
                guard abs(usersContentHeight - newHeight) > 0.5 else {
                    return
                }

                usersContentHeight = newHeight
            }
        }
    }

    @ViewBuilder
    private var librariesContent: some View {
        if let errorMessage = libraryStore.errorMessage, libraryStore.libraries.isEmpty {
            EmptyStateView(
                icon: "books.vertical",
                title: "Couldn’t Load Libraries",
                message: errorMessage,
                actionTitle: "Refresh"
            ) {
                refreshAllData()
            }
        } else if libraryStore.libraries.isEmpty {
            EmptyStateView(
                icon: "books.vertical",
                title: "No Libraries Found",
                message: "PlexBar didn’t find any visible libraries on this server yet."
            )
        } else {
            ScrollView {
                LibrariesDashboardView(
                    settingsStore: settingsStore,
                    serverURL: connectionStore.resolvedServerURL,
                    libraryStore: libraryStore
                )
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: MenuBarContentHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    }
            }
            .frame(height: libraryListHeight, alignment: .top)
            .onPreferenceChange(MenuBarContentHeightPreferenceKey.self) { newHeight in
                guard abs(libraryContentHeight - newHeight) > 0.5 else {
                    return
                }

                libraryContentHeight = newHeight
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh") {
                refreshAllData()
            }
            .disabled(!settingsStore.hasValidConfiguration)

            Button("Settings") {
                openSettings()
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.bordered)
    }

    private var subtitle: String {
        if !settingsStore.hasValidConfiguration {
            return "Configure your Plex connection"
        }

        let serverLabel = settingsStore.selectedServerName?.nilIfBlank
            ?? connectionStore.resolvedServerURL?.host
            ?? "your server"

        switch selectedSection {
        case .streams:
            let count = sessionStore.activeStreamCount
            let streamsLabel = count == 1 ? "1 stream" : "\(count) streams"

            if let lastUpdated = sessionStore.lastUpdated {
                return "\(streamsLabel) on \(serverLabel) • Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
            }

            return "\(streamsLabel) on \(serverLabel)"
        case .history:
            let count = historyStore.totalPlayCount
            let historyLabel = count == 1
                ? "1 watch in \(historyStore.historyWindowLabel.lowercased())"
                : "\(count) watches in \(historyStore.historyWindowLabel.lowercased())"

            if let lastUpdated = historyStore.lastUpdated {
                return "\(historyLabel) on \(serverLabel) • Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
            }

            return "\(historyLabel) on \(serverLabel)"
        case .users:
            let viewerCount = historyStore.distinctViewerCount
            let userLabel = viewerCount == 1
                ? "1 user in \(historyStore.historyWindowLabel.lowercased())"
                : "\(viewerCount) users in \(historyStore.historyWindowLabel.lowercased())"

            if let lastUpdated = historyStore.lastUpdated {
                return "\(userLabel) on \(serverLabel) • Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
            }

            return "\(userLabel) on \(serverLabel)"
        case .libraries:
            let libraryLabel = libraryStore.libraryCount == 1
                ? "1 library"
                : "\(libraryStore.libraryCount) libraries"
            let itemLabel = libraryStore.totalItemCount == 1
                ? "1 item"
                : "\(libraryStore.totalItemCount.formatted()) items"

            if let lastUpdated = libraryStore.lastUpdated {
                return "\(libraryLabel) • \(itemLabel) on \(serverLabel) • Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
            }

            return "\(libraryLabel) • \(itemLabel) on \(serverLabel)"
        }
    }

    private func refreshAllData() {
        sessionStore.refreshNow()
        historyStore.refreshNow()
    }

    private func presentTerminatePrompt(for session: PlexSession) {
        terminateMessage = ""
        terminatePrompt = TerminatePlaybackPrompt(session: session)
    }

    private func toggleExpandedStream(_ session: PlexSession) {
        expandedStreamID = expandedStreamID == session.id ? nil : session.id
    }

    private func dismissTerminatePrompt() {
        terminatePrompt = nil
        terminateMessage = ""
    }

    private func confirmTerminate(_ session: PlexSession) {
        let reason = terminateMessage
        dismissTerminatePrompt()

        Task {
            await sessionStore.terminate(session, reason: reason)
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettingsWindow()
    }

    private var streamListHeight: CGFloat {
        boundedHeight(for: streamContentHeight, minimum: 132)
    }

    private var historyListHeight: CGFloat {
        boundedHeight(for: historyContentHeight, minimum: 320)
    }

    private var usersListHeight: CGFloat {
        boundedHeight(for: usersContentHeight, minimum: 320)
    }

    private var libraryListHeight: CGFloat {
        boundedHeight(for: libraryContentHeight, minimum: 320)
    }

    private func boundedHeight(for measuredHeight: CGFloat, minimum: CGFloat) -> CGFloat {
        guard measuredHeight > 0 else {
            return minimum
        }

        return min(max(measuredHeight, minimum), maximumContentHeight)
    }

    private var maximumContentHeight: CGFloat {
        let fallbackHeight: CGFloat = 760
        guard let visibleFrame = activeScreen?.visibleFrame else {
            return fallbackHeight
        }

        let reservedVerticalChrome: CGFloat = 180
        let screenAwareHeight = max(visibleFrame.height - reservedVerticalChrome, 360)
        return min(screenAwareHeight, fallbackHeight)
    }

    private var activeScreen: NSScreen? {
        NSScreen.screens.first { screen in
            NSMouseInRect(NSEvent.mouseLocation, screen.frame, false)
        } ?? NSScreen.main
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case streams
    case history
    case users
    case libraries

    var id: String { rawValue }

    var title: String {
        switch self {
        case .streams:
            "Active Streams"
        case .history:
            "Watch History"
        case .users:
            "Users"
        case .libraries:
            "Libraries"
        }
    }

    var controlTitle: String {
        switch self {
        case .streams:
            "Streams"
        case .history:
            "History"
        case .users:
            "Users"
        case .libraries:
            "Libraries"
        }
    }

    var systemImage: String {
        switch self {
        case .streams:
            "play.rectangle.on.rectangle"
        case .history:
            "clock.arrow.circlepath"
        case .users:
            "person.2"
        case .libraries:
            "books.vertical"
        }
    }

    @MainActor
    func isLoading(
        sessionStore: PlexSessionStore,
        historyStore: PlexHistoryStore,
        libraryStore: PlexLibraryStore
    ) -> Bool {
        switch self {
        case .streams:
            sessionStore.isLoading
        case .history:
            historyStore.isLoading
        case .users:
            historyStore.isLoading
        case .libraries:
            libraryStore.isLoading
        }
    }

    @MainActor
    func inlineErrorMessage(
        sessionStore: PlexSessionStore,
        historyStore: PlexHistoryStore,
        libraryStore: PlexLibraryStore
    ) -> String? {
        switch self {
        case .streams:
            guard !sessionStore.sessions.isEmpty else {
                return nil
            }

            return sessionStore.errorMessage
        case .history:
            guard !historyStore.recentItems.isEmpty else {
                return nil
            }

            return historyStore.errorMessage
        case .users:
            guard !historyStore.recentItems.isEmpty else {
                return nil
            }

            return historyStore.errorMessage
        case .libraries:
            guard !libraryStore.libraries.isEmpty else {
                return nil
            }

            return libraryStore.errorMessage
        }
    }
}

private struct TerminatePlaybackPrompt: Identifiable {
    let session: PlexSession

    var id: String {
        session.id
    }
}

private struct MenuBarContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct InlineWarningBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.22))
        }
    }
}
