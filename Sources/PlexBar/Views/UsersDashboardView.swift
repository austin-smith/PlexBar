import SwiftUI

struct UsersDashboardView: View {
    let settingsStore: PlexSettingsStore
    let serverURL: URL?
    let historyStore: PlexHistoryStore

    private var clientContext: PlexClientContext {
        PlexClientContext(clientIdentifier: settingsStore.clientIdentifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !historyStore.topUserEntries.isEmpty {
                TopUsersCard(
                    entries: historyStore.topUserEntries,
                    settingsStore: settingsStore,
                    serverURL: serverURL,
                    clientContext: clientContext
                )
            }

            if !historyStore.topUserEntries.isEmpty {
                UserFormatMixCard(
                    entries: Array(historyStore.topUserEntries.prefix(4)),
                    settingsStore: settingsStore,
                    serverURL: serverURL,
                    clientContext: clientContext
                )
            }

            if !historyStore.recentViewerEntries.isEmpty {
                RecentUsersCard(
                    entries: historyStore.recentViewerEntries,
                    settingsStore: settingsStore,
                    serverURL: serverURL,
                    clientContext: clientContext
                )
            }
        }
    }
}

private struct TopUsersCard: View {
    let entries: [PlexUserActivityEntry]
    let settingsStore: PlexSettingsStore
    let serverURL: URL?
    let clientContext: PlexClientContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Top Users")
                    .font(.headline)

                Text("Who has watched the most in the last 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    TopUserRow(
                        rank: index + 1,
                        entry: entry,
                        settingsStore: settingsStore,
                        serverURL: serverURL,
                        clientContext: clientContext
                    )
                }
            }
        }
        .padding(16)
        .dashboardPanel(accent: .green.opacity(0.12))
    }
}

private struct TopUserRow: View {
    let rank: Int
    let entry: PlexUserActivityEntry
    let settingsStore: PlexSettingsStore
    let serverURL: URL?
    let clientContext: PlexClientContext

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)

            PlexAvatarView(
                thumb: entry.thumb,
                serverURL: serverURL,
                serverToken: settingsStore.trimmedServerToken,
                userToken: settingsStore.trimmedUserToken,
                clientContext: clientContext,
                size: 34
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(formatSummary(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let recentSummary = recentSummary(for: entry) {
                    Text(recentSummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(entry.playCount == 1 ? "1" : "\(entry.playCount)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.08), in: Capsule())
        }
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatSummary(for entry: PlexUserActivityEntry) -> String {
        let parts = [
            entry.moviePlayCount > 0 ? "\(entry.moviePlayCount) movie\(entry.moviePlayCount == 1 ? "" : "s")" : nil,
            entry.tvPlayCount > 0 ? "\(entry.tvPlayCount) TV" : nil,
            entry.musicPlayCount > 0 ? "\(entry.musicPlayCount) music" : nil,
        ]
        .compactMap { $0 }

        guard !parts.isEmpty else {
            return entry.playCount == 1 ? "1 play" : "\(entry.playCount) plays"
        }

        return parts.joined(separator: " • ")
    }

    private func recentSummary(for entry: PlexUserActivityEntry) -> String? {
        let relative = entry.lastViewedAt.map(Self.relativeDescription(for:))
        let title = entry.lastPlayedTitle?.nilIfBlank
        let parts = [title, relative].compactMap { $0?.nilIfBlank }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private static func relativeDescription(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct UserFormatMixCard: View {
    let entries: [PlexUserActivityEntry]
    let settingsStore: PlexSettingsStore
    let serverURL: URL?
    let clientContext: PlexClientContext

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("User Mix")
                    .font(.headline)

                Text("What each heavy user has been watching recently")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            PlexAvatarView(
                                thumb: entry.thumb,
                                serverURL: serverURL,
                                serverToken: settingsStore.trimmedServerToken,
                                userToken: settingsStore.trimmedUserToken,
                                clientContext: clientContext,
                                size: 24
                            )

                            Text(entry.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            MixMetricRow(
                                label: "Movies",
                                symbolName: PlexSessionContentKind.movie.symbolName,
                                value: entry.moviePlayCount
                            )
                            MixMetricRow(
                                label: "TV",
                                symbolName: PlexSessionContentKind.tv.symbolName,
                                value: entry.tvPlayCount
                            )
                            MixMetricRow(
                                label: "Music",
                                symbolName: PlexSessionContentKind.track.symbolName,
                                value: entry.musicPlayCount
                            )
                        }

                        Spacer(minLength: 0)

                        Text(entry.playCount == 1 ? "1 total play" : "\(entry.playCount) total plays")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
                    .padding(14)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(16)
        .dashboardPanel(accent: .blue.opacity(0.12))
    }
}

private struct MixMetricRow: View {
    let label: String
    let symbolName: String
    let value: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 12)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text("\(value)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
    }
}

private struct RecentUsersCard: View {
    let entries: [PlexUserActivityEntry]
    let settingsStore: PlexSettingsStore
    let serverURL: URL?
    let clientContext: PlexClientContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent Users")
                    .font(.headline)

                Text("The people who watched something most recently")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(entries) { entry in
                    HStack(spacing: 12) {
                        PlexAvatarView(
                            thumb: entry.thumb,
                            serverURL: serverURL,
                            serverToken: settingsStore.trimmedServerToken,
                            userToken: settingsStore.trimmedUserToken,
                            clientContext: clientContext,
                            size: 30
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if let recentSummary = recentSummary(for: entry) {
                                Text(recentSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(12)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(16)
        .dashboardPanel(accent: .orange.opacity(0.12))
    }

    private func recentSummary(for entry: PlexUserActivityEntry) -> String? {
        let relative = entry.lastViewedAt.map(Self.relativeDescription(for:))
        let title = entry.lastPlayedTitle?.nilIfBlank
        let parts = [title, relative].compactMap { $0?.nilIfBlank }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private static func relativeDescription(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
