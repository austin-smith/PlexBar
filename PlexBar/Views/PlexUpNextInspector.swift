import PlexClientKit
import PlexModels
import SwiftUI

struct PlexUpNextHUD: View {
    let session: PlexPlayerSessionModel
    @State private var pendingUpcomingItemIDs: [String]?

    var body: some View {
        queueList
            .frame(width: 440, height: hudHeight)
            .overlay {
                if session.isUpdatingQueue {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .background(.regularMaterial, in: .circle)
                        .accessibilityLabel("Updating Up Next")
                }
            }
        .task {
            await session.refreshQueueWindow()
        }
        .onChange(of: session.queuePresentation?.upcomingItems.map(\.id)) {
            pendingUpcomingItemIDs = nil
        }
        .onChange(of: session.isUpdatingQueue) { wasUpdating, isUpdating in
            if wasUpdating, !isUpdating {
                pendingUpcomingItemIDs = nil
            }
        }
    }

    private var hudHeight: CGFloat {
        guard let queue = session.queuePresentation else {
            return 142
        }
        let visibleRowCount = min(queue.upcomingItems.count, 5)
        return min(max(170 + CGFloat(visibleRowCount) * 74, 220), 520)
    }

    private var queueList: some View {
        List {
            Section("Playing Now") {
                PlexQueueItemRow(
                    item: session.queuePresentation?.currentItem ?? session.presentation.item,
                    serverURL: session.artworkServerURL,
                    token: session.artworkToken,
                    clientContext: session.artworkClientContext,
                    isNowPlaying: true,
                    play: nil,
                    queueActions: nil
                )
            }

            if let queue = session.queuePresentation,
               !queue.upcomingItems.isEmpty {
                Section("Next") {
                    ForEach(displayedUpcomingItems(in: queue)) { item in
                        PlexUpcomingQueueItemRow(
                            item: item,
                            session: session
                        )
                        .moveDisabled(!session.canReorderUpcomingItems)
                    }
                    .onMove(perform: moveUpcomingItems)
                }
            }

            if let queueErrorMessage = session.queueErrorMessage,
               session.queuePresentation != nil {
                Section("Queue Error") {
                    Text(queueErrorMessage)
                        .foregroundStyle(.secondary)

                    Button("Refresh Queue", action: session.requestQueueRefresh)
                        .disabled(session.isUpdatingQueue || session.isLoading)
                }
            }

            if let queue = session.queuePresentation {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        if queue.isShuffled {
                            Label("Shuffled", systemImage: "shuffle")
                        }
                        Text("Item \(queue.currentPosition.formatted()) of \(queue.totalCount.formatted())")
                        if queue.unloadedRemainingCount > 0 {
                            Text("\(queue.unloadedRemainingCount.formatted()) additional items remain on the server.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func displayedUpcomingItems(
        in queue: PlexPlaybackQueuePresentation
    ) -> [PlexMediaItem] {
        guard let pendingUpcomingItemIDs,
              pendingUpcomingItemIDs.count == queue.upcomingItems.count else {
            return queue.upcomingItems
        }
        let itemsByID = Dictionary(
            uniqueKeysWithValues: queue.upcomingItems.map { ($0.id, $0) }
        )
        let reorderedItems = pendingUpcomingItemIDs.compactMap { itemsByID[$0] }
        return reorderedItems.count == queue.upcomingItems.count
            ? reorderedItems
            : queue.upcomingItems
    }

    private func moveUpcomingItems(
        fromOffsets sourceOffsets: IndexSet,
        toOffset destinationOffset: Int
    ) {
        guard let queue = session.queuePresentation,
              session.moveUpcomingItems(
                  fromOffsets: sourceOffsets,
                  toOffset: destinationOffset
              ) else {
            return
        }
        var reorderedItems = displayedUpcomingItems(in: queue)
        reorderedItems.move(
            fromOffsets: sourceOffsets,
            toOffset: destinationOffset
        )
        pendingUpcomingItemIDs = reorderedItems.map(\.id)
    }
}

private struct PlexUpcomingQueueItemRow: View {
    let item: PlexMediaItem
    let session: PlexPlayerSessionModel

    var body: some View {
        PlexQueueItemRow(
            item: item,
            serverURL: session.artworkServerURL,
            token: session.artworkToken,
            clientContext: session.artworkClientContext,
            isNowPlaying: false,
            play: play,
            queueActions: queueActions
        )
        .disabled(session.isLoading || session.isUpdatingQueue)
    }

    private var play: (() -> Void)? {
        guard let playQueueItemID = item.playQueueItemID?.nilIfBlank else {
            return nil
        }
        return {
            session.playUpcomingItem(playQueueItemID: playQueueItemID)
        }
    }

    private var queueActions: PlexQueueItemActions? {
        guard let playQueueItemID = item.playQueueItemID?.nilIfBlank else {
            return nil
        }
        return PlexQueueItemActions(
            play: {
                session.playUpcomingItem(playQueueItemID: playQueueItemID)
            },
            moveUp: {
                session.moveUpcomingItem(
                    playQueueItemID: playQueueItemID,
                    direction: .up
                )
            },
            moveDown: {
                session.moveUpcomingItem(
                    playQueueItemID: playQueueItemID,
                    direction: .down
                )
            },
            remove: {
                session.removeUpcomingItem(playQueueItemID: playQueueItemID)
            },
            canMoveUp: session.canMoveUpcomingItem(
                playQueueItemID: playQueueItemID,
                direction: .up
            ),
            canMoveDown: session.canMoveUpcomingItem(
                playQueueItemID: playQueueItemID,
                direction: .down
            ),
            canRemove: session.canRemoveUpcomingItem(
                playQueueItemID: playQueueItemID
            )
        )
    }
}

private struct PlexQueueItemActions {
    let play: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canRemove: Bool
}

private struct PlexQueueItemActionMenuItems: View {
    let actions: PlexQueueItemActions

    var body: some View {
        Button("Play Now", systemImage: "play.fill", action: actions.play)

        Divider()

        Button("Move Up", systemImage: "arrow.up", action: actions.moveUp)
            .disabled(!actions.canMoveUp)

        Button("Move Down", systemImage: "arrow.down", action: actions.moveDown)
            .disabled(!actions.canMoveDown)

        Divider()

        Button(
            "Remove from Up Next",
            systemImage: "minus.circle",
            role: .destructive,
            action: actions.remove
        )
        .disabled(!actions.canRemove)
    }
}

private struct PlexQueueItemRow: View {
    let item: PlexMediaItem
    let serverURL: URL?
    let token: String
    let clientContext: PlexClientContext
    let isNowPlaying: Bool
    let play: (() -> Void)?
    let queueActions: PlexQueueItemActions?
    @ScaledMetric(relativeTo: .body) private var audioArtworkSize: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var videoArtworkWidth: CGFloat = 42
    @ScaledMetric(relativeTo: .body) private var videoArtworkHeight: CGFloat = 62

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if let play {
                    Button(action: play) {
                        rowContent
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Plays this item from the queue.")
                } else {
                    rowContent
                }
            }

            if let queueActions {
                Menu("Queue Actions", systemImage: "ellipsis.circle") {
                    PlexQueueItemActionMenuItems(actions: queueActions)
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
                .help("Queue Actions")
            }
        }
        .contextMenu {
            if let queueActions {
                PlexQueueItemActionMenuItems(actions: queueActions)
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
    }

    private var rowContent: some View {
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
                    .font(.body.weight(isNowPlaying ? .semibold : .regular))
                    .lineLimit(2)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isNowPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var artworkURL: URL? {
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: item.posterArtworkPath)
    }

    private var artworkWidth: CGFloat {
        item.continuousPlayQueueType == .audio ? audioArtworkSize : videoArtworkWidth
    }

    private var artworkHeight: CGFloat {
        item.continuousPlayQueueType == .audio ? audioArtworkSize : videoArtworkHeight
    }

    private var accessibilityLabel: String {
        [isNowPlaying ? "Now Playing" : nil, item.title, item.subtitle]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: ", ")
    }
}
