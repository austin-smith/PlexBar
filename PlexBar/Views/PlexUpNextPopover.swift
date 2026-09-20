import PlexClientKit
import PlexModels
import SwiftUI

struct PlexUpNextPopover: View {
    let session: PlexPlayerSessionModel
    let maximumHeight: CGFloat
    @Environment(\.dismiss) private var dismiss
    @State private var pendingUpcomingItemIDs: [String]?
    @State private var requestedPlaybackID: String?
    @State private var selectedUpcomingItemID: String?
    @FocusState private var isQueueFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if session.isUpdatingQueue || session.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Updating Up Next")
                }
            }
            .padding(16)

            Divider()
            queueList
        }
        .frame(width: 380, height: min(preferredHeight, maximumHeight))
        .font(.body)
        .buttonStyle(.automatic)
        .labelStyle(.titleAndIcon)
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
        .onChange(of: session.engine.status) { dismissAfterRequestedPlaybackStarts() }
        .onChange(of: session.isLoading) { dismissAfterRequestedPlaybackStarts() }
    }

    private var preferredHeight: CGFloat {
        let visibleRowCount = min(session.queuePresentation?.upcomingItems.count ?? 0, 4)
        return min(220 + CGFloat(visibleRowCount) * 72, 440)
    }

    private func play(_ item: PlexMediaItem) {
        guard !session.isLoading, !session.isUpdatingQueue,
              let id = item.playQueueItemID?.nilIfBlank else { return }
        requestedPlaybackID = id
        session.playUpcomingItem(playQueueItemID: id)
    }

    private func dismissAfterRequestedPlaybackStarts() {
        guard let requestedPlaybackID, !session.isLoading,
              session.engine.status == .playing,
              session.queuePresentation?.currentItem.playQueueItemID == requestedPlaybackID else { return }
        dismiss()
    }

    private var queueList: some View {
        List(selection: $selectedUpcomingItemID) {
            Section("Playing Now") {
                PlexQueueItemRow(
                    item: session.queuePresentation?.currentItem ?? session.presentation.item,
                    serverURL: session.artworkServerURL,
                    token: session.artworkToken,
                    clientContext: session.artworkClientContext,
                    isNowPlaying: true
                )
            }
            .listSectionSeparator(.hidden)

            if let queue = session.queuePresentation,
               !queue.upcomingItems.isEmpty {
                Section("Next") {
                    ForEach(displayedUpcomingItems(in: queue)) { item in
                        PlexUpcomingQueueItemRow(
                            item: item,
                            session: session,
                            isKeyboardSelected: isQueueFocused && selectedUpcomingItemID == item.id,
                            play: { play(item) }
                        )
                        .tag(item.id)
                        .moveDisabled(!session.canReorderUpcomingItems)
                    }
                    .onMove(perform: moveUpcomingItems)
                }
                .listSectionSeparator(.hidden)
            } else {
                Section("Next") {
                    Text("No upcoming items")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                .listSectionSeparator(.hidden)
            }

            if let queueErrorMessage = session.queueErrorMessage,
               session.queuePresentation != nil {
                Section("Queue Error") {
                    Text(queueErrorMessage)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)

                    Button("Refresh Queue", action: session.requestQueueRefresh)
                        .disabled(session.isUpdatingQueue || session.isLoading)
                        .listRowSeparator(.hidden)
                }
                .listSectionSeparator(.hidden)
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
                    .listRowSeparator(.hidden)
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .focused($isQueueFocused)
        .contextMenu(forSelectionType: String.self) { ids in
            if let item = upcomingItem(in: ids) {
                PlexQueueItemActionMenuItems(item: item, session: session, play: { play(item) })
            }
        } primaryAction: { ids in
            if let item = upcomingItem(in: ids) {
                play(item)
            }
        }
        .onDeleteCommand {
            guard let id = selectedUpcomingItemID,
                  let item = upcomingItem(in: [id]),
                  let queueItemID = item.playQueueItemID else { return }
            session.removeUpcomingItem(playQueueItemID: queueItemID)
        }
        .background {
            PlexQueueKeyboardShortcuts(move: moveSelectedItem)
                .frame(width: 0, height: 0)
        }
    }

    private func upcomingItem(in ids: Set<String>) -> PlexMediaItem? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return session.queuePresentation?.upcomingItems.first { $0.id == id }
    }

    private func moveSelectedItem(_ direction: PlexPlayQueueItemMoveDirection) -> Bool {
        guard isQueueFocused,
              let item = session.queuePresentation?.upcomingItems.first(where: { $0.id == selectedUpcomingItemID }),
              let id = item.playQueueItemID?.nilIfBlank else { return false }
        session.moveUpcomingItem(playQueueItemID: id, direction: direction)
        return true
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
    let isKeyboardSelected: Bool
    let play: () -> Void

    var body: some View {
        let queueItemID = item.playQueueItemID?.nilIfBlank
        let playAction: (() -> Void)? = queueItemID == nil ? nil : play
        let removeAction: (() -> Void)? = queueItemID == nil ? nil : { remove() }
        let canRemove = queueItemID.map { session.canRemoveUpcomingItem(playQueueItemID: $0) } ?? false

        PlexQueueItemRow(
            item: item,
            serverURL: session.artworkServerURL,
            token: session.artworkToken,
            clientContext: session.artworkClientContext,
            isNowPlaying: false,
            isKeyboardSelected: isKeyboardSelected,
            play: playAction,
            remove: removeAction,
            canRemove: canRemove,
            canReorder: session.canReorderUpcomingItems
        )
        .disabled(session.isLoading || session.isUpdatingQueue)
        .accessibilityActions {
            PlexQueueItemActionMenuItems(item: item, session: session, play: play)
        }
    }

    private func remove() {
        guard let id = item.playQueueItemID?.nilIfBlank else { return }
        session.removeUpcomingItem(playQueueItemID: id)
    }
}

private struct PlexQueueItemActionMenuItems: View {
    let item: PlexMediaItem
    let session: PlexPlayerSessionModel
    let play: () -> Void

    var body: some View {
        if let id = item.playQueueItemID?.nilIfBlank {
            Button("Play Now", systemImage: "play.fill", action: play)
                .disabled(session.isLoading || session.isUpdatingQueue)

            Button("Move Up", systemImage: "arrow.up") {
                session.moveUpcomingItem(playQueueItemID: id, direction: .up)
            }
            .disabled(!session.canMoveUpcomingItem(playQueueItemID: id, direction: .up))

            Button("Move Down", systemImage: "arrow.down") {
                session.moveUpcomingItem(playQueueItemID: id, direction: .down)
            }
            .disabled(!session.canMoveUpcomingItem(playQueueItemID: id, direction: .down))

            Button("Remove from Up Next", systemImage: "minus.circle", role: .destructive) {
                session.removeUpcomingItem(playQueueItemID: id)
            }
            .disabled(!session.canRemoveUpcomingItem(playQueueItemID: id))
        }
    }
}

private struct PlexQueueItemRow: View {
    let item: PlexMediaItem
    let serverURL: URL?
    let token: String
    let clientContext: PlexClientContext
    let isNowPlaying: Bool
    var isKeyboardSelected = false
    var play: (() -> Void)?
    var remove: (() -> Void)?
    var canRemove = false
    var canReorder = false
    @ScaledMetric(relativeTo: .body) private var audioArtworkSize: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var videoArtworkWidth: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var videoArtworkHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var minimumContentHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var subtitleSize: CGFloat = 11
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable {
        case play
        case remove
    }

    private var showsControls: Bool {
        isHovered || isKeyboardSelected || focusedControl != nil
    }

    var body: some View {
        HStack(spacing: 10) {
            if let play {
                Button(action: play) {
                    artwork.overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(.black.opacity(0.28))
                            Image(systemName: "play.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                        }
                        .opacity(showsControls ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showsControls)
                        .allowsHitTesting(false)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focused($focusedControl, equals: .play)
                .accessibilityLabel("Play \(accessibilityLabel)")
                .help("Play Now")
            } else {
                artwork
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: titleSize, weight: isNowPlaying ? .semibold : .medium))
                    .lineLimit(2)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: subtitleSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHidden(play != nil)

            if let remove {
                HStack(spacing: 4) {
                    Button(role: .destructive, action: remove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .opacity(showsControls ? 1 : 0)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showsControls)
                            .frame(width: 24, height: 28)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .focused($focusedControl, equals: .remove)
                    .disabled(!canRemove)
                    .accessibilityLabel("Remove \(item.title) from Up Next")
                    .help("Remove from Up Next")

                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 28)
                        .opacity(canReorder ? 1 : 0)
                        .help("Drag to Reorder")
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(minHeight: minimumContentHeight)
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
        .onHover { isHovered = $0 }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .listRowSeparator(.hidden)
    }

    private var artwork: some View {
        PlexArtworkView(
            primaryImageURL: artworkURL,
            fallbackImageURL: nil,
            token: token,
            clientContext: clientContext,
            placeholderSymbol: item.placeholderSymbol,
            width: artworkWidth,
            height: artworkHeight,
            cornerRadius: 5
        )
        .accessibilityHidden(true)
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
        [isNowPlaying ? "Now Playing" : nil, item.title, subtitle]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: ", ")
    }

    private var subtitle: String? {
        guard item.type == "episode" else { return item.subtitle }
        return [item.grandparentTitle?.nilIfBlank, item.episodeIdentifier]
            .compactMap { $0 }.joined(separator: " · ").nilIfBlank
    }
}
