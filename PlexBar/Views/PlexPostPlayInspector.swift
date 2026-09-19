import PlexModels
import SwiftUI

struct PlexPlaybackEndedOverlay: View {
    let session: PlexPlayerSessionModel
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    content(scrollsSuggestions: true)
                }
                .padding(20)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 20) {
                    header
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            content(scrollsSuggestions: false)
                        }
                    }
                }
                .padding(20)
            }
            .frame(width: min(460, geometry.size.width))
            .background(.regularMaterial, in: .rect(cornerRadius: 18))
            .clipShape(.rect(cornerRadius: 18))
            .shadow(radius: 24, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 48)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback Finished")
    }

    private var header: some View {
        HStack {
            Text(session.postPlayNextItem == nil ? "More to Watch" : "Up Next")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

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
    }

    @ViewBuilder
    private func content(scrollsSuggestions: Bool) -> some View {
        if session.postPlayNextItem != nil || !session.postPlayHubs.isEmpty {
            if let nextItem = session.postPlayNextItem {
                playingNextItem(nextItem)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !suggestionHubs.isEmpty || session.postPlayErrorMessage != nil {
                if scrollsSuggestions {
                    ScrollView {
                        suggestions
                    }
                    .frame(height: suggestionsHeight)
                    .defaultScrollAnchor(.top)
                } else {
                    suggestions
                }
            }
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

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(suggestionHubs) { hub in
                VStack(alignment: .leading, spacing: 10) {
                    Text(hub.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(postPlayItems(in: hub)) { item in
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

            if let errorMessage = session.postPlayErrorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Refresh Error")
                        .font(.subheadline.weight(.semibold))
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                    Button("Try Again", action: session.requestPostPlayRefresh)
                        .disabled(session.isLoadingPostPlay || session.isLoading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var suggestionHubs: [PlexHub] {
        session.postPlayHubs.filter { !postPlayItems(in: $0).isEmpty }
    }

    @ScaledMetric(relativeTo: .body) private var suggestionRowHeight: CGFloat = 54
    @ScaledMetric(relativeTo: .subheadline) private var suggestionHeadingHeight: CGFloat = 16

    private var suggestionsHeight: CGFloat {
        // Show the first heading and two complete rows, with further suggestions scrolling.
        guard let firstHub = suggestionHubs.first else { return 120 }
        let rowCount = min(postPlayItems(in: firstHub).count, 2)
        return suggestionHeadingHeight + CGFloat(rowCount) * (suggestionRowHeight + 10)
    }

    private func playingNextItem(_ item: PlexMediaItem) -> some View {
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
    @ScaledMetric(relativeTo: .body) private var artworkWidth: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var artworkHeight: CGFloat = 120

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
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

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
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
                            .monospacedDigit()
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
            .frame(maxWidth: .infinity, minHeight: artworkHeight, alignment: .topLeading)
        }
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
    @ScaledMetric(relativeTo: .body) private var artworkWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var artworkHeight: CGFloat = 54

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
    }

    private var artworkURL: URL? {
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: item.posterArtworkPath)
    }
}
