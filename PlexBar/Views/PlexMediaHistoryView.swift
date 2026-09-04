import SwiftUI

struct PlexMediaHistoryView: View {
    let item: PlexMediaItem
    let historyStore: PlexHistoryStore
    let settingsStore: PlexSettingsStore
    let serverURL: URL?

    var body: some View {
        if let presentation = historyStore.mediaHistoryPresentation(for: item),
            presentation.isVisible
        {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Watch History")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)

                    Spacer(minLength: 12)

                    if !presentation.items.isEmpty {
                        Text(summary(for: presentation.items.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                PlexMediaHistoryContent(
                    sourceItem: item,
                    presentation: presentation,
                    historyStore: historyStore,
                    settingsStore: settingsStore,
                    serverURL: serverURL
                )
            }
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private func summary(for playCount: Int) -> String {
        let plays = playCount == 1 ? "1 play" : "\(playCount) plays"
        return "\(plays) · \(historyStore.historyWindowLabel)"
    }
}

struct PlexMediaHistoryListSection: View {
    let item: PlexMediaItem
    let historyStore: PlexHistoryStore
    let settingsStore: PlexSettingsStore
    let serverURL: URL?

    var body: some View {
        if let presentation = historyStore.mediaHistoryPresentation(for: item),
            presentation.isVisible
        {
            Section {
                PlexMediaHistoryContent(
                    sourceItem: item,
                    presentation: presentation,
                    historyStore: historyStore,
                    settingsStore: settingsStore,
                    serverURL: serverURL
                )
            } header: {
                Text("Watch History")
            } footer: {
                if !presentation.items.isEmpty {
                    Text(historyStore.historyWindowLabel)
                }
            }
        }
    }
}

private struct PlexMediaHistoryContent: View {
    private static let visibleItemLimit = 5

    let sourceItem: PlexMediaItem
    let presentation: PlexMediaHistoryPresentation
    let historyStore: PlexHistoryStore
    let settingsStore: PlexSettingsStore
    let serverURL: URL?

    private var visibleItems: [PlexHistoryItem] {
        Array(presentation.items.prefix(Self.visibleItemLimit))
    }

    var body: some View {
        if presentation.items.isEmpty {
            if presentation.isLoading {
                ProgressView("Loading Watch History…")
                    .accessibilityLabel("Loading watch history for \(sourceItem.title)")
            } else if presentation.errorMessage != nil {
                historyError
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, historyItem in
                    mediaHistoryRow(for: historyItem)

                    if index < visibleItems.count - 1 {
                        Divider()
                    }
                }

                if presentation.items.count > visibleItems.count {
                    Text("Showing the latest \(visibleItems.count) of \(presentation.items.count) plays")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }

                if presentation.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 8)
                        .accessibilityLabel("Refreshing watch history for \(sourceItem.title)")
                } else if presentation.errorMessage != nil {
                    historyError
                        .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func mediaHistoryRow(for historyItem: PlexHistoryItem) -> some View {
        let account = historyItem.watcherAccount(using: historyStore.accountsByID)
        let device = historyItem.playbackDevice(using: historyStore.devicesByID)
        let route = historyItem.mediaRoute
        let canNavigate = route?.ratingKey != sourceItem.ratingKey

        if canNavigate, let route {
            NavigationLink(value: PlexNavigationRoute.media(route)) {
                PlexMediaHistoryRow(
                    historyItem: historyItem,
                    account: account,
                    device: device,
                    settingsStore: settingsStore,
                    serverURL: serverURL,
                    showsNavigationIndicator: true
                )
            }
            .buttonStyle(.plain)
        } else {
            PlexMediaHistoryRow(
                historyItem: historyItem,
                account: account,
                device: device,
                settingsStore: settingsStore,
                serverURL: serverURL,
                showsNavigationIndicator: false
            )
        }
    }

    private var historyError: some View {
        HStack(spacing: 10) {
            Label("Couldn’t Load Watch History", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Try Again") {
                Task {
                    await historyStore.loadMediaHistory(for: sourceItem, forceRefresh: true)
                }
            }
            .controlSize(.small)
        }
    }
}

private struct PlexMediaHistoryRow: View {
    let historyItem: PlexHistoryItem
    let account: PlexAccount?
    let device: PlexHistoryDevice?
    let settingsStore: PlexSettingsStore
    let serverURL: URL?
    let showsNavigationIndicator: Bool

    private var presentation: PlexMediaHistoryRowPresentation {
        PlexMediaHistoryRowPresentation(
            item: historyItem,
            account: account,
            device: device
        )
    }

    private var clientContext: PlexClientContext {
        PlexClientContext(clientIdentifier: settingsStore.clientIdentifier)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PlexArtworkView(
                primaryImageURL: artworkURL,
                fallbackImageURL: transcodedArtworkURL,
                token: settingsStore.trimmedServerToken,
                clientContext: clientContext,
                placeholderSymbol: historyItem.contentKind.symbolName,
                width: 46,
                height: 64,
                cornerRadius: 8
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let subtitle = presentation.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 7) {
                    if let account {
                        PlexAvatarView(
                            thumb: account.thumb,
                            serverURL: serverURL,
                            serverToken: settingsStore.trimmedServerToken,
                            userToken: settingsStore.trimmedUserToken,
                            clientContext: clientContext,
                            size: 18
                        )
                    } else {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(.secondary)
                    }

                    Text(presentation.contextLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let viewedAt = historyItem.viewedAt {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewedAt, format: .dateTime.month(.abbreviated).day().year())
                    Text(viewedAt, format: .dateTime.hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            } else {
                Text("Date unavailable")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if showsNavigationIndicator {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var artworkURL: URL? {
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(
            serverURL: serverURL,
            path: historyItem.posterPath(spoilerPolicy: settingsStore.episodeSpoilerPolicy)
        )
    }

    private var transcodedArtworkURL: URL? {
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.transcodedArtworkURL(
            serverURL: serverURL,
            path: historyItem.posterPath(spoilerPolicy: settingsStore.episodeSpoilerPolicy),
            width: 92,
            height: 128
        )
    }
}
