import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var authStore: PlexAuthStore
    @Bindable var sessionStore: PlexSessionStore
    @Bindable var historyStore: PlexHistoryStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedSection: DashboardSection = .streams
    @State private var streamContentHeight: CGFloat = 0
    @State private var historyContentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionPicker
            header
            content
            footer
        }
        .padding(16)
        .frame(width: 420)
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
        }
    }

    private var sectionPicker: some View {
        Picker("Dashboard Section", selection: $selectedSection) {
            ForEach(DashboardSection.allCases) { section in
                Text(section.controlTitle)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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
            }

            if let inlineErrorMessage = selectedSection.inlineErrorMessage(
                sessionStore: sessionStore,
                historyStore: historyStore
            ) {
                Text(inlineErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                        StreamCardView(session: session, settingsStore: settingsStore)
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
                HistoryDashboardView(settingsStore: settingsStore, historyStore: historyStore)
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
            ?? settingsStore.normalizedServerURL?.host
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
        }
    }

    private func refreshAllData() {
        sessionStore.refreshNow()
        historyStore.refreshNow()
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: AppConstants.settingsWindowID)
    }

    private var streamListHeight: CGFloat {
        boundedHeight(for: streamContentHeight, minimum: 132)
    }

    private var historyListHeight: CGFloat {
        boundedHeight(for: historyContentHeight, minimum: 320)
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .streams:
            "Active Streams"
        case .history:
            "Watch History"
        }
    }

    var controlTitle: String {
        switch self {
        case .streams:
            "Streams"
        case .history:
            "History"
        }
    }

    @MainActor
    func isLoading(sessionStore: PlexSessionStore, historyStore: PlexHistoryStore) -> Bool {
        switch self {
        case .streams:
            sessionStore.isLoading
        case .history:
            historyStore.isLoading
        }
    }

    @MainActor
    func inlineErrorMessage(
        sessionStore: PlexSessionStore,
        historyStore: PlexHistoryStore
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
        }
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
