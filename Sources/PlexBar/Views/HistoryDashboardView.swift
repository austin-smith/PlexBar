import SwiftUI

struct HistoryDashboardView: View {
    let settingsStore: PlexSettingsStore
    let historyStore: PlexHistoryStore

    private var clientContext: PlexClientContext {
        PlexClientContext(clientIdentifier: settingsStore.clientIdentifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !historyStore.recentItems.isEmpty {
                TopChartsCard(
                    title: "Top Titles",
                    items: historyStore.recentItems,
                    accountsByID: historyStore.accountsByID,
                    seriesByEpisodeID: historyStore.seriesByEpisodeID,
                    historyWindowLabel: historyStore.historyWindowLabel,
                    settingsStore: settingsStore,
                    clientContext: clientContext
                )
            }

            if !historyStore.topTypeEntries.isEmpty {
                HistoryMixCard(
                    entries: historyStore.topTypeEntries,
                    accountsByID: historyStore.accountsByID,
                    settingsStore: settingsStore,
                    clientContext: clientContext
                )
            }

            if !historyStore.recentItems.isEmpty {
                RecentPlaysCard(
                    items: historyStore.recentItems,
                    historyWindowLabel: historyStore.historyWindowLabel,
                    settingsStore: settingsStore,
                    clientContext: clientContext,
                    accountsByID: historyStore.accountsByID
                )
            }
        }
    }
}

private struct RecentPlaysCard: View {
    let items: [PlexHistoryItem]
    let historyWindowLabel: String
    let settingsStore: PlexSettingsStore
    let clientContext: PlexClientContext
    let accountsByID: [Int: PlexAccount]

    @State private var selectedFilter: PlexHistoryContentFilter = .all

    private var filteredItems: [PlexHistoryItem] {
        PlexHistoryAnalytics.recentItems(from: items, filter: selectedFilter, limit: 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Plays")
                        .font(.headline)

                    Text(historyWindowLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                HistorySectionFilterPicker(selection: $selectedFilter)
            }

            if filteredItems.isEmpty {
                Text(emptyStateMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredItems) { item in
                        RecentHistoryCardView(
                            item: item,
                            watcherName: item.watcherName(using: accountsByID),
                            watcherAccount: item.watcherAccount(using: accountsByID),
                            settingsStore: settingsStore,
                            clientContext: clientContext
                        )
                    }
                }
            }
        }
        .padding(16)
        .dashboardPanel(accent: .orange.opacity(0.12))
    }

    private var emptyStateMessage: String {
        switch selectedFilter {
        case .all:
            "No recent plays found for this history window."
        case .movies:
            "No recent movie plays in the last 30 days."
        case .tv:
            "No recent TV plays in the last 30 days."
        }
    }
}

private struct TopChartsCard: View {
    let title: String
    let items: [PlexHistoryItem]
    let accountsByID: [Int: PlexAccount]
    let seriesByEpisodeID: [String: PlexHistorySeriesIdentity]
    let historyWindowLabel: String
    let settingsStore: PlexSettingsStore
    let clientContext: PlexClientContext

    @State private var selectedFilter: PlexHistoryContentFilter = .all

    private var entries: [PlexTopChartEntry] {
        PlexHistoryAnalytics.topTitleEntries(
            from: items,
            accountsByID: accountsByID,
            seriesByEpisodeID: seriesByEpisodeID,
            limit: 5,
            filter: selectedFilter
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)

                    Text(historyWindowLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                HistorySectionFilterPicker(selection: $selectedFilter)
            }

            if entries.isEmpty {
                Text(selectedFilter.emptyStateMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        TopChartRow(
                            rank: index + 1,
                            entry: entry,
                            accountsByID: accountsByID,
                            settingsStore: settingsStore,
                            clientContext: clientContext
                        )
                    }
                }
            }
        }
        .padding(16)
        .dashboardPanel(accent: .red.opacity(0.14))
    }
}

private struct HistorySectionFilterPicker: View {
    @Binding var selection: PlexHistoryContentFilter

    var body: some View {
        Picker("Filter", selection: $selection) {
            ForEach(PlexHistoryContentFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

private struct TopChartRow: View {
    let rank: Int
    let entry: PlexTopChartEntry
    let accountsByID: [Int: PlexAccount]
    let settingsStore: PlexSettingsStore
    let clientContext: PlexClientContext

    private var watcherAccounts: [PlexAccount] {
        entry.watcherAccountIDs.compactMap { accountsByID[$0] }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)

            PlexArtworkView(
                primaryImageURL: posterURL,
                fallbackImageURL: transcodedPosterURL,
                token: settingsStore.trimmedServerToken,
                clientContext: clientContext,
                placeholderSymbol: entry.symbolName ?? "play.square",
                width: 40,
                height: 56,
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HistoryWatcherIdentityView(
                    summary: entry.watcherSummary ?? entry.viewerCountLabel,
                    accounts: watcherAccounts,
                    settingsStore: settingsStore,
                    clientContext: clientContext,
                    avatarSize: 16,
                    font: .caption2,
                    foregroundStyle: .tertiary
                )
            }

            Spacer(minLength: 8)

            Text(entry.playCount == 1 ? "1" : "\(entry.playCount)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.08), in: Capsule())
        }
    }

    private var posterURL: URL? {
        guard let serverURL = settingsStore.normalizedServerURL else {
            return nil
        }

        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: entry.posterPath)
    }

    private var transcodedPosterURL: URL? {
        guard let serverURL = settingsStore.normalizedServerURL else {
            return nil
        }

        return PlexURLBuilder.transcodedArtworkURL(
            serverURL: serverURL,
            path: entry.posterPath,
            width: 80,
            height: 112
        )
    }
}

private struct HistoryMixCard: View {
    let entries: [PlexTopChartEntry]
    let accountsByID: [Int: PlexAccount]
    let settingsStore: PlexSettingsStore
    let clientContext: PlexClientContext

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Format Mix")
                    .font(.headline)

                Text("A quick view of what has been watched recently")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: entry.symbolName ?? "play.square")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.subheadline.weight(.semibold))

                            Text(entry.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            HistoryWatcherIdentityView(
                                summary: entry.watcherSummary ?? entry.viewerCountLabel,
                                accounts: entry.watcherAccountIDs.compactMap { accountsByID[$0] },
                                settingsStore: settingsStore,
                                clientContext: clientContext,
                                avatarSize: 16,
                                font: .caption2,
                                foregroundStyle: .tertiary,
                                lineLimit: 2
                            )
                        }

                        Spacer(minLength: 0)

                        Text(entry.playCount == 1 ? "1" : "\(entry.playCount)")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                    .padding(14)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(16)
        .dashboardPanel(accent: .blue.opacity(0.12))
    }
}

private struct RecentHistoryCardView: View {
    let item: PlexHistoryItem
    let watcherName: String?
    let watcherAccount: PlexAccount?
    let settingsStore: PlexSettingsStore
    let clientContext: PlexClientContext

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlexArtworkView(
                primaryImageURL: posterURL,
                fallbackImageURL: transcodedPosterURL,
                token: settingsStore.trimmedServerToken,
                clientContext: clientContext,
                placeholderSymbol: item.contentKind.symbolName,
                width: 58,
                height: 80,
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.headline)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let detailLine = item.detailLine {
                    Text(detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Label(item.contentKind.displayName, systemImage: item.contentKind.symbolName)
                    if let viewedAtDescription = item.viewedAtRelativeDescription {
                        Text(viewedAtDescription)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HistoryWatcherIdentityView(
                    summary: watcherName,
                    accounts: watcherAccount.map { [$0] } ?? [],
                    settingsStore: settingsStore,
                    clientContext: clientContext,
                    avatarSize: 18,
                    font: .caption.weight(.medium),
                    foregroundStyle: .secondary
                )
            }

            Spacer(minLength: 8)
        }
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var posterURL: URL? {
        guard let serverURL = settingsStore.normalizedServerURL else {
            return nil
        }

        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: item.posterPath)
    }

    private var transcodedPosterURL: URL? {
        guard let serverURL = settingsStore.normalizedServerURL else {
            return nil
        }

        return PlexURLBuilder.transcodedArtworkURL(
            serverURL: serverURL,
            path: item.posterPath,
            width: 116,
            height: 160
        )
    }
}

private struct HistoryWatcherIdentityView: View {
    let summary: String?
    let accounts: [PlexAccount]
    let settingsStore: PlexSettingsStore
    let clientContext: PlexClientContext
    let avatarSize: CGFloat
    let font: Font
    let foregroundStyle: HierarchicalShapeStyle
    var lineLimit: Int = 1

    private var displayAccounts: [PlexAccount] {
        Array(accounts.prefix(3))
    }

    var body: some View {
        if let summary = summary?.nilIfBlank {
            HStack(spacing: 8) {
                if displayAccounts.count == 1, let account = displayAccounts.first {
                    PlexAvatarView(
                        thumb: account.thumb,
                        serverURL: settingsStore.normalizedServerURL,
                        serverToken: settingsStore.trimmedServerToken,
                        userToken: settingsStore.trimmedUserToken,
                        clientContext: clientContext,
                        size: avatarSize
                    )
                } else if !displayAccounts.isEmpty {
                    WatcherAvatarStack(
                        accounts: displayAccounts,
                        settingsStore: settingsStore,
                        clientContext: clientContext,
                        size: avatarSize
                    )
                }

                Text(summary)
                    .font(font)
                    .foregroundStyle(foregroundStyle)
                    .lineLimit(lineLimit)
            }
        }
    }
}

private struct WatcherAvatarStack: View {
    let accounts: [PlexAccount]
    let settingsStore: PlexSettingsStore
    let clientContext: PlexClientContext
    let size: CGFloat

    private var overlapOffset: CGFloat {
        size * 0.42
    }

    private var width: CGFloat {
        size + CGFloat(max(accounts.count - 1, 0)) * overlapOffset
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                PlexAvatarView(
                    thumb: account.thumb,
                    serverURL: settingsStore.normalizedServerURL,
                    serverToken: settingsStore.trimmedServerToken,
                    userToken: settingsStore.trimmedUserToken,
                    clientContext: clientContext,
                    size: size
                )
                .overlay {
                    Circle()
                        .stroke(.black.opacity(0.22), lineWidth: 1)
                }
                .offset(x: CGFloat(index) * overlapOffset)
                .zIndex(Double(accounts.count - index))
            }
        }
        .frame(width: width, height: size, alignment: .leading)
    }
}

struct DashboardPanelModifier: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        content
            .background {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.7),
                                Color.white.opacity(0.035),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(.thinMaterial, in: shape)
            }
            .overlay {
                shape.strokeBorder(.white.opacity(0.08))
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

extension View {
    func dashboardPanel(accent: Color) -> some View {
        modifier(DashboardPanelModifier(accent: accent))
    }
}
