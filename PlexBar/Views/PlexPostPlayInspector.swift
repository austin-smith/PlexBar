import SwiftUI

struct PlexPlaybackEndedOverlay: View {
    let session: PlexPlayerSessionModel
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(width: 520, height: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 24, y: 10)
        .padding(32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback Finished")
    }

    private var header: some View {
        HStack {
            Text(session.postPlayNextItem == nil ? "More to Watch" : "Up Next")
                .font(.headline)

            Spacer()

            if session.isLoadingPostPlay {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading post-play items")
            }

            Button("Refresh", systemImage: "arrow.clockwise", action: session.requestPostPlayRefresh)
                .labelStyle(.iconOnly)
                .disabled(session.isLoadingPostPlay || session.isLoading)
                .help("Refresh Suggestions")

            Button("Close", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .help("Close")
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if session.postPlayNextItem != nil || !session.postPlayHubs.isEmpty {
            List {
                if let nextItem = session.postPlayNextItem {
                    playingNextSection(nextItem)
                }

                ForEach(session.postPlayHubs) { hub in
                    let additionalItems = postPlayItems(in: hub)
                    if !additionalItems.isEmpty {
                        Section(hub.title) {
                            ForEach(additionalItems) { item in
                                PlexPostPlayItemRow(
                                    item: item,
                                    serverURL: session.artworkServerURL,
                                    token: session.artworkToken,
                                    clientContext: session.artworkClientContext,
                                    action: { session.playPostPlayItem(item) }
                                )
                                .disabled(session.isLoading)
                            }
                        }
                    }
                }

                if let errorMessage = session.postPlayErrorMessage {
                    Section("Refresh Error") {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                        Button("Try Again", action: session.requestPostPlayRefresh)
                            .disabled(session.isLoadingPostPlay || session.isLoading)
                    }
                }
            }
            .listStyle(.inset)
        } else {
            if session.isLoadingPostPlay {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading post-play items")
            } else if let errorMessage = session.postPlayErrorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Suggestions", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again", action: session.requestPostPlayRefresh)
                }
            } else {
                ContentUnavailableView("Nothing Else to Play", systemImage: "checkmark.circle")
            }
        }
    }

    private func postPlayItems(in hub: PlexHub) -> [PlexMediaItem] {
        guard let nextItem = session.postPlayNextItem else {
            return hub.metadata
        }
        return hub.metadata.filter {
            !($0.ratingKey == nextItem.ratingKey
                && ($0.playQueueItemID?.nilIfBlank == nil
                    || $0.playQueueItemID?.nilIfBlank == nextItem.playQueueItemID?.nilIfBlank))
        }
    }

    private func playingNextSection(_ item: PlexMediaItem) -> some View {
        Section("Playing Next") {
            PlexPostPlayNextItem(
                item: item,
                serverURL: session.artworkServerURL,
                token: session.artworkToken,
                clientContext: session.artworkClientContext,
                countdownTotalSeconds: session.postPlayCountdownTotalSeconds,
                countdownRemainingSeconds: session.postPlayCountdownRemainingSeconds,
                isLoading: session.isLoading,
                play: session.playPostPlayNextItem,
                cancelAutoplay: session.cancelPostPlayAutoplay
            )
        }
    }
}

private struct PlexPostPlayNextItem: View {
    let item: PlexMediaItem
    let serverURL: URL?
    let token: String
    let clientContext: PlexClientContext
    let countdownTotalSeconds: Int?
    let countdownRemainingSeconds: Int?
    let isLoading: Bool
    let play: () -> Void
    let cancelAutoplay: () -> Void
    @ScaledMetric(relativeTo: .body) private var artworkWidth: CGFloat = 72
    @ScaledMetric(relativeTo: .body) private var artworkHeight: CGFloat = 106

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PlexArtworkView(
                    primaryImageURL: artworkURL,
                    fallbackImageURL: nil,
                    token: token,
                    clientContext: clientContext,
                    placeholderSymbol: item.placeholderSymbol,
                    width: artworkWidth,
                    height: artworkHeight,
                    cornerRadius: 8
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(3)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let countdownTotalSeconds,
               let countdownRemainingSeconds {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(
                        value: Double(countdownRemainingSeconds),
                        total: Double(countdownTotalSeconds)
                    )
                    .accessibilityLabel("Time Until Auto Play")
                    .accessibilityValue("\(countdownRemainingSeconds) seconds")

                    Text("Playing in \(countdownRemainingSeconds) seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Play Now", systemImage: "play.fill", action: play)
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)

                if countdownRemainingSeconds != nil {
                    Button("Cancel Auto Play", action: cancelAutoplay)
                        .disabled(isLoading)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var artworkURL: URL? {
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: item.posterArtworkPath)
    }
}

private struct PlexPostPlayItemRow: View {
    let item: PlexMediaItem
    let serverURL: URL?
    let token: String
    let clientContext: PlexClientContext
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var artworkWidth: CGFloat = 42
    @ScaledMetric(relativeTo: .body) private var artworkHeight: CGFloat = 62

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PlexArtworkView(
                    primaryImageURL: artworkURL,
                    fallbackImageURL: nil,
                    token: token,
                    clientContext: clientContext,
                    placeholderSymbol: item.placeholderSymbol,
                    width: artworkWidth,
                    height: artworkHeight,
                    cornerRadius: 6
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body)
                        .lineLimit(2)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([item.title, item.subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Starts this post-play item.")
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
    }

    private var artworkURL: URL? {
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: item.posterArtworkPath)
    }
}
