import SwiftUI

struct PlexWatchedStateButton: View {
    @Binding var item: PlexMediaItem
    @Bindable var browserStore: PlexBrowserStore
    @State private var errorMessage: String?

    var body: some View {
        if browserStore.supportsWatchedStateMutation(for: item) {
            Button(action: updateWatchedState) {
                if browserStore.isUpdatingWatchedState(for: item) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(item.watchedActionTitle, systemImage: item.watchedActionSystemImage)
                }
            }
            .disabled(browserStore.isUpdatingWatchedState(for: item))
            .accessibilityLabel(item.watchedActionTitle)
            .plexMutationErrorAlert(
                title: "Couldn’t Update Watched Status",
                message: $errorMessage
            )
        }
    }

    private func updateWatchedState() {
        let watched = !item.isWatched
        Task {
            do {
                item = try await browserStore.setWatched(watched, for: item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PlexPersonalRatingMenu: View {
    @Binding var item: PlexMediaItem
    @Bindable var browserStore: PlexBrowserStore
    @State private var errorMessage: String?
    @State private var isRatingPopoverPresented = false

    var body: some View {
        if browserStore.supportsPersonalRatings {
            Button {
                isRatingPopoverPresented.toggle()
            } label: {
                if browserStore.isUpdatingPersonalRating(for: item) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(item.personalRatingTitle, systemImage: item.personalRatingSystemImage)
                }
            }
            .disabled(browserStore.isUpdatingPersonalRating(for: item))
            .accessibilityLabel(item.personalRatingAccessibilityLabel)
            .popover(isPresented: $isRatingPopoverPresented, arrowEdge: .bottom) {
                ratingPopover
            }
            .plexMutationErrorAlert(
                title: "Couldn’t Update Rating",
                message: $errorMessage
            )
        }
    }

    private var ratingPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Rating")
                .font(.headline)

            PlexStarRatingPicker(
                serverValue: item.userRating,
                isDisabled: browserStore.isUpdatingPersonalRating(for: item),
                onSelect: updateRating
            )

            Divider()

            Button("Clear Rating", systemImage: "xmark.circle", action: clearRating)
                .disabled(item.userRating == nil)
        }
        .padding()
    }

    private func clearRating() {
        updateRating(nil)
    }

    private func updateRating(_ rating: Double?) {
        isRatingPopoverPresented = false
        Task {
            do {
                item = try await browserStore.setPersonalRating(rating, for: item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PlexMetadataRefreshButton: View {
    let item: PlexMediaItem
    @Bindable var browserStore: PlexBrowserStore
    @State private var errorMessage: String?

    var body: some View {
        if browserStore.supportsMetadataRefresh(for: item) {
            Button(action: refreshMetadata) {
                if browserStore.isRefreshingMetadata(for: item) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh Metadata", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
            }
            .disabled(browserStore.isRefreshingMetadata(for: item))
            .accessibilityLabel("Refresh metadata for \(item.title)")
            .plexMutationErrorAlert(
                title: "Couldn’t Refresh Metadata",
                message: $errorMessage
            )
        }
    }

    private func refreshMetadata() {
        Task {
            do {
                try await browserStore.refreshMetadata(for: item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PlexPlaybackQueueMenu: View {
    let item: PlexMediaItem
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    @State private var errorMessage: String?

    var body: some View {
        if playerCoordinator.canAddToQueue(item) {
            Menu {
                Button("Play Next", systemImage: "text.insert", action: playNext)
                Button("Add to Up Next", systemImage: "text.badge.plus", action: addToUpNext)
            } label: {
                if playerCoordinator.isAddingToQueue {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Queue", systemImage: "text.badge.plus")
                }
            }
            .disabled(playerCoordinator.isAddingToQueue)
            .accessibilityLabel("Queue \(item.title)")
            .plexMutationErrorAlert(
                title: "Couldn’t Update Up Next",
                message: $errorMessage
            )
        }
    }

    private func playNext() {
        add(insertion: .next)
    }

    private func addToUpNext() {
        add(insertion: .upNext)
    }

    private func add(insertion: PlexPlayQueueInsertion) {
        Task {
            do {
                try await playerCoordinator.addToQueue(item, insertion: insertion)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PlexMediaContextMenuModifier: ViewModifier {
    @Environment(PlexDownloadsStore.self) private var downloadsStore
    let item: PlexMediaItem
    let parent: PlexMediaItem?
    let library: PlexLibrary?
    let allowsRemovalFromContinueWatching: Bool
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    @State private var errorMessage: String?
    @State private var isConfirmingRemoval = false
    @State private var isRatingPopoverPresented = false
    @State private var presentedOrganizationRequest: PlexMediaOrganizationRequest?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                PlexMediaHierarchyNavigationMenu(destinations: item.hierarchyDestinations)

                if !item.hierarchyDestinations.isEmpty, hasActionsAfterHierarchyNavigation {
                    Divider()
                }

                if showsDownloadAction {
                    if downloadsStore.containsDownload(for: item) {
                        Button("Downloaded", systemImage: "checkmark.circle.fill") {}
                            .disabled(true)
                    } else if downloadsStore.isDownloading(item) {
                        Button("Downloading", systemImage: "arrow.down.circle") {}
                            .disabled(true)
                    } else {
                        Button("Download", systemImage: "arrow.down.circle", action: download)
                    }
                }

                if browserStore.supportsWatchedStateMutation(for: item) {
                    Button(action: updateWatchedState) {
                        Label(item.watchedActionTitle, systemImage: item.watchedActionSystemImage)
                    }
                    .disabled(browserStore.isUpdatingWatchedState(for: item))
                }

                if browserStore.supportsPersonalRatings {
                    Button {
                        isRatingPopoverPresented = true
                    } label: {
                        Label(item.personalRatingTitle, systemImage: item.personalRatingSystemImage)
                    }
                    .disabled(browserStore.isUpdatingPersonalRating(for: item))
                }

                if playerCoordinator.canAddToQueue(item) {
                    Divider()

                    Button("Play Next", systemImage: "text.insert", action: playNext)
                        .disabled(playerCoordinator.isAddingToQueue)
                    Button("Add to Up Next", systemImage: "text.badge.plus", action: addToUpNext)
                        .disabled(playerCoordinator.isAddingToQueue)
                }

                if allowsRemovalFromContinueWatching,
                   browserStore.supportsRemoveFromContinueWatching {
                    Button(
                        "Remove from Continue Watching",
                        systemImage: "rectangle.badge.xmark",
                        action: removeFromContinueWatching
                    )
                    .disabled(browserStore.isRemovingFromContinueWatching(item))
                }

                if browserStore.supportsMetadataRefresh(for: item) {
                    Divider()

                    Button(action: refreshMetadata) {
                        Label("Refresh Metadata", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    }
                    .disabled(browserStore.isRefreshingMetadata(for: item))
                }

                if let parent, browserStore.supportsChildManagement(of: parent) {
                    Divider()

                    Button("Move Up", systemImage: "arrow.up", action: moveUp)
                        .disabled(
                            browserStore.isManagingCollectionOrPlaylist(parent)
                                || !browserStore.canMoveChild(item, in: parent, direction: .up)
                        )
                    Button("Move Down", systemImage: "arrow.down", action: moveDown)
                        .disabled(
                            browserStore.isManagingCollectionOrPlaylist(parent)
                                || !browserStore.canMoveChild(item, in: parent, direction: .down)
                        )

                    Divider()

                    Button(removalTitle(for: parent), systemImage: "minus.circle", role: .destructive) {
                        isConfirmingRemoval = true
                    }
                    .disabled(browserStore.isManagingCollectionOrPlaylist(parent))
                }

                if library != nil,
                   item.playlistMediaType != nil,
                   browserStore.supportsCollectionManagement || browserStore.supportsPlaylistCreation {
                    Divider()

                    if browserStore.supportsCollectionManagement {
                        Button("Add to Collection…", systemImage: "rectangle.stack.badge.plus") {
                            presentedOrganizationRequest = .collection
                        }
                    }
                    if browserStore.supportsPlaylistCreation {
                        Button("Add to Playlist…", systemImage: "text.badge.plus") {
                            presentedOrganizationRequest = .playlist
                        }
                    }
                }
            }
            .plexMutationErrorAlert(
                title: "Couldn’t Update Item",
                message: $errorMessage
            )
            .popover(isPresented: $isRatingPopoverPresented, arrowEdge: .bottom) {
                ratingPopover
            }
            .confirmationDialog(
                removalConfirmationTitle,
                isPresented: $isConfirmingRemoval
            ) {
                Button(removalConfirmationButtonTitle, role: .destructive, action: removeFromParent)
            } message: {
                Text(removalConfirmationMessage)
            }
            .sheet(item: $presentedOrganizationRequest) { request in
                switch request {
                case .collection:
                    if let library {
                        PlexAddToCollectionSheet(
                            item: item,
                            library: library,
                            browserStore: browserStore
                        )
                    }
                case .playlist:
                    PlexAddToPlaylistSheet(item: item, browserStore: browserStore)
                }
            }
    }

    private var hasActionsAfterHierarchyNavigation: Bool {
        showsDownloadAction
            || browserStore.supportsWatchedStateMutation(for: item)
            || browserStore.supportsPersonalRatings
            || playerCoordinator.canAddToQueue(item)
            || (allowsRemovalFromContinueWatching && browserStore.supportsRemoveFromContinueWatching)
            || browserStore.supportsMetadataRefresh(for: item)
            || (parent.map(browserStore.supportsChildManagement(of:)) ?? false)
            || (
                library != nil
                    && item.playlistMediaType != nil
                    && (browserStore.supportsCollectionManagement || browserStore.supportsPlaylistCreation)
            )
    }

    private var showsDownloadAction: Bool {
        downloadsStore.containsDownload(for: item)
            || downloadsStore.isDownloading(item)
            || downloadsStore.canCreateDownload(for: item, libraryID: library?.id)
    }

    private var ratingPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Rating")
                .font(.headline)

            PlexStarRatingPicker(
                serverValue: item.userRating,
                isDisabled: browserStore.isUpdatingPersonalRating(for: item),
                onSelect: updateRating
            )

            Divider()

            Button("Clear Rating", systemImage: "xmark.circle", action: clearRating)
                .disabled(item.userRating == nil)
        }
        .padding()
    }

    private func updateWatchedState() {
        let watched = !item.isWatched
        Task {
            do {
                try await browserStore.setWatched(watched, for: item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func download() {
        Task {
            do {
                try await downloadsStore.download(item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearRating() {
        updateRating(nil)
    }

    private func updateRating(_ rating: Double?) {
        isRatingPopoverPresented = false
        Task {
            do {
                try await browserStore.setPersonalRating(rating, for: item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshMetadata() {
        Task {
            do {
                try await browserStore.refreshMetadata(for: item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeFromContinueWatching() {
        Task {
            do {
                try await browserStore.removeFromContinueWatching(item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func playNext() {
        addToQueue(insertion: .next)
    }

    private func addToUpNext() {
        addToQueue(insertion: .upNext)
    }

    private func addToQueue(insertion: PlexPlayQueueInsertion) {
        Task {
            do {
                try await playerCoordinator.addToQueue(item, insertion: insertion)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func moveUp() {
        move(.up)
    }

    private func moveDown() {
        move(.down)
    }

    private func move(_ direction: PlexListMoveDirection) {
        guard let parent else {
            return
        }
        Task {
            do {
                try await browserStore.moveChild(item, in: parent, direction: direction)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeFromParent() {
        guard let parent else {
            return
        }
        Task {
            do {
                try await browserStore.removeChild(item, from: parent)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removalTitle(for parent: PlexMediaItem) -> String {
        parent.type?.lowercased() == "collection"
            ? "Remove from Collection"
            : "Remove from Playlist"
    }

    private var removalConfirmationTitle: String {
        guard let parent else {
            return "Remove Item?"
        }
        return parent.type?.lowercased() == "collection"
            ? "Remove from Collection?"
            : "Remove from Playlist?"
    }

    private var removalConfirmationButtonTitle: String {
        guard let parent else {
            return "Remove"
        }
        return removalTitle(for: parent)
    }

    private var removalConfirmationMessage: String {
        guard let parent else {
            return ""
        }
        return "This removes \(item.title) from \(parent.title). The media file is not deleted."
    }
}

extension View {
    func plexMediaContextMenu(
        for item: PlexMediaItem,
        in parent: PlexMediaItem? = nil,
        library: PlexLibrary? = nil,
        allowsRemovalFromContinueWatching: Bool = false,
        browserStore: PlexBrowserStore,
        playerCoordinator: PlexPlayerCoordinator
    ) -> some View {
        modifier(PlexMediaContextMenuModifier(
            item: item,
            parent: parent,
            library: library,
            allowsRemovalFromContinueWatching: allowsRemovalFromContinueWatching,
            browserStore: browserStore,
            playerCoordinator: playerCoordinator
        ))
    }

    func plexMutationErrorAlert(
        title: String,
        message: Binding<String?>
    ) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        message.wrappedValue = nil
                    }
                }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(message.wrappedValue ?? "Unknown Plex error.")
        }
    }
}

extension PlexMediaItem {
    var watchedActionTitle: String {
        isWatched ? "Mark as Unwatched" : "Mark as Watched"
    }

    var watchedActionSystemImage: String {
        isWatched ? "eye.slash" : "eye"
    }

    var personalRatingTitle: String {
        PlexPersonalRating.title(forServerValue: userRating)
    }

    var personalRatingAccessibilityLabel: String {
        guard PlexPersonalRating.stars(fromServerValue: userRating) != nil else {
            return "Rate \(title)"
        }
        return "Your rating for \(title) is \(PlexPersonalRating.accessibilityValue(forServerValue: userRating))"
    }

    var personalRatingSystemImage: String {
        userRating == nil ? "star" : "star.fill"
    }
}
