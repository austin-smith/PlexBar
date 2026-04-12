import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var authStore: PlexAuthStore
    @Bindable var sessionStore: PlexSessionStore
    @Environment(\.openWindow) private var openWindow
    @State private var streamContentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            footer
        }
        .padding(16)
        .frame(width: 420)
    }

    private var header: some View {
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
    }

    @ViewBuilder
    private var content: some View {
        if !settingsStore.hasValidConfiguration {
            EmptyStateView(
                title: settingsStore.hasAuthenticatedAccount ? "Choose a Server" : "Connect Plex",
                message: settingsStore.hasAuthenticatedAccount
                    ? "PlexBar signed in successfully, but no Plex Media Server is selected yet."
                    : "Sign in with Plex to discover your servers and start watching active streams.",
                actionTitle: "Open Settings"
            ) {
                openSettings()
            }
        } else {
            if let errorMessage = sessionStore.errorMessage, sessionStore.sessions.isEmpty {
                EmptyStateView(
                    title: "Couldn’t Reach Plex",
                    message: errorMessage,
                    actionTitle: "Refresh"
                ) {
                    sessionStore.refreshNow()
                }
            } else if sessionStore.sessions.isEmpty {
                EmptyStateView(
                    title: "No Active Streams",
                    message: "Nothing is currently playing on this server.",
                    actionTitle: "Refresh"
                ) {
                    sessionStore.refreshNow()
                }
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
                                .preference(key: StreamContentHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    }
                }
                .frame(height: streamListHeight, alignment: .top)
                .onPreferenceChange(StreamContentHeightPreferenceKey.self) { newHeight in
                    guard abs(streamContentHeight - newHeight) > 0.5 else {
                        return
                    }

                    streamContentHeight = newHeight
                }
            }

            if let errorMessage = sessionStore.errorMessage, !sessionStore.sessions.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh") {
                sessionStore.refreshNow()
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
        let count = sessionStore.activeStreamCount
        let streamsLabel = count == 1 ? "1 stream" : "\(count) streams"

        if let lastUpdated = sessionStore.lastUpdated {
            return "\(streamsLabel) on \(serverLabel) • Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
        }

        return "\(streamsLabel) on \(serverLabel)"
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: AppConstants.settingsWindowID)
    }

    private var streamListHeight: CGFloat {
        guard streamContentHeight > 0 else { return 132 }
        return min(streamContentHeight, maximumStreamListHeight)
    }

    private var maximumStreamListHeight: CGFloat {
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

private struct StreamContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct EmptyStateView: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
