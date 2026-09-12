import SwiftUI

struct TVPlaybackQueueHostView: View {
    let store: TVAppStore
    let presentation: PlexPlaybackQueuePresentation
    let canSelectItems: Bool
    let play: (String) -> Void
    let move: (String, PlexPlayQueueItemMoveDirection) -> Void
    let remove: (String) -> Void

    var body: some View {
        TVPlaybackQueueView(
            presentation: presentation,
            canSelectItems: canSelectItems,
            play: play,
            move: move,
            remove: remove
        )
        .environment(store)
    }
}

private struct TVPlaybackQueueView: View {
    let presentation: PlexPlaybackQueuePresentation
    let canSelectItems: Bool
    let play: (String) -> Void
    let move: (String, PlexPlayQueueItemMoveDirection) -> Void
    let remove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text("Up Next")
                    .font(TVTypography.title)

                Spacer()

                Text(positionLabel)
                    .font(TVTypography.cardTitle)
                    .foregroundStyle(.secondary)
            }
            .safeAreaPadding(.horizontal)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: TVLayout.cardSpacing) {
                    TVPlaybackQueueCurrentCard(item: presentation.currentItem)

                    ForEach(presentation.upcomingItems) { item in
                        TVPlaybackQueueButton(
                            item: item,
                            presentation: presentation,
                            canSelectItems: canSelectItems,
                            play: play,
                            move: move,
                            remove: remove
                        )
                    }

                    if presentation.unloadedRemainingCount > 0 {
                        TVPlaybackQueueRemainingCard(
                            count: presentation.unloadedRemainingCount
                        )
                    }
                }
                .safeAreaPadding(.horizontal)
                .padding(.vertical, 16)
            }
            .scrollClipDisabled()
            .buttonStyle(.borderless)
        }
        .safeAreaPadding(.vertical)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Up Next")
    }

    private var positionLabel: String {
        "\(presentation.currentPosition) of \(presentation.totalCount)"
    }
}

private struct TVPlaybackQueueCurrentCard: View {
    let item: PlexMediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TVPlaybackQueueArtwork(item: item)
                .overlay(alignment: .bottomLeading) {
                    Label("Now Playing", systemImage: "waveform")
                        .font(TVTypography.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(12)
                }

            TVPlaybackQueueLabels(item: item)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now Playing, \(item.title)")
    }
}

private struct TVPlaybackQueueButton: View {
    let item: PlexMediaItem
    let presentation: PlexPlaybackQueuePresentation
    let canSelectItems: Bool
    let play: (String) -> Void
    let move: (String, PlexPlayQueueItemMoveDirection) -> Void
    let remove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: playNow) {
                TVPlaybackQueueArtwork(item: item)
                    .hoverEffect(.highlight)
            }
            .buttonStyle(.borderless)
            .disabled(!canPlay)
            .accessibilityLabel(item.title)
            .accessibilityValue(item.contextTitle ?? "")
            .accessibilityHint("Play this item now")
            .contextMenu {
                Button("Play Now", systemImage: "play.fill", action: playNow)
                    .disabled(!canPlay)

                Divider()

                Button("Move Earlier", systemImage: "arrow.left", action: moveEarlier)
                    .disabled(!canMoveEarlier)

                Button("Move Later", systemImage: "arrow.right", action: moveLater)
                    .disabled(!canMoveLater)

                Divider()

                Button(
                    "Remove from Up Next",
                    systemImage: "minus.circle",
                    role: .destructive,
                    action: removeFromQueue
                )
                .disabled(!canRemove)
            }

            TVMediaCardLabels(
                title: item.title,
                subtitle: item.contextTitle
            )
            .accessibilityHidden(true)
        }
    }

    private var playQueueItemID: String? {
        item.playQueueItemID?.nilIfBlank
    }

    private var canPlay: Bool {
        canSelectItems && playQueueItemID != nil
    }

    private var canMoveEarlier: Bool {
        guard canSelectItems, let playQueueItemID else { return false }
        return presentation.canMoveUpcomingItem(
            playQueueItemID: playQueueItemID,
            direction: .up
        )
    }

    private var canMoveLater: Bool {
        guard canSelectItems, let playQueueItemID else { return false }
        return presentation.canMoveUpcomingItem(
            playQueueItemID: playQueueItemID,
            direction: .down
        )
    }

    private var canRemove: Bool {
        canSelectItems
            && presentation.canRemoveUpcomingItems
            && playQueueItemID != nil
    }

    private func playNow() {
        guard let playQueueItemID else { return }
        play(playQueueItemID)
    }

    private func moveEarlier() {
        guard let playQueueItemID else { return }
        move(playQueueItemID, .up)
    }

    private func moveLater() {
        guard let playQueueItemID else { return }
        move(playQueueItemID, .down)
    }

    private func removeFromQueue() {
        guard let playQueueItemID else { return }
        remove(playQueueItemID)
    }
}

private struct TVPlaybackQueueArtwork: View {
    let item: PlexMediaItem

    var body: some View {
        TVPlexArtwork(
            path: item.preferredBackdropPath,
            width: 660,
            height: 372,
            systemImage: item.type?.lowercased() == "track" ? "music.note" : "film"
        )
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .containerRelativeFrame(.horizontal, count: 4, spacing: TVLayout.cardSpacing)
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct TVPlaybackQueueLabels: View {
    let item: PlexMediaItem

    var body: some View {
        TVMediaCardLabels(
            title: item.title,
            subtitle: item.contextTitle
        )
    }
}

private struct TVPlaybackQueueRemainingCard: View {
    let count: Int

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "ellipsis")
                .font(.title)
            Text("\(count) more on this server")
                .font(TVTypography.cardTitle)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .containerRelativeFrame(.horizontal, count: 4, spacing: TVLayout.cardSpacing)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(.quaternary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
