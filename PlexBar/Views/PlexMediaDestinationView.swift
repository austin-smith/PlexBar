import PlexClientKit
import PlexModels
import SwiftUI

struct PlexMediaDestinationView: View {
    let initialItem: PlexMediaItem
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var historyStore: PlexHistoryStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    let refreshesInitialMetadata: Bool

    var body: some View {
        if initialItem.type?.lowercased() == "show" {
            PlexTVShowDetailView(
                initialShow: initialItem,
                browserStore: browserStore,
                historyStore: historyStore,
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                playerCoordinator: playerCoordinator,
                refreshesInitialMetadata: refreshesInitialMetadata
            )
        } else if initialItem.type?.lowercased() == "episode",
                  initialItem.grandparentRatingKey?.nilIfBlank != nil {
            PlexTVEpisodeDestinationView(
                initialEpisode: initialItem,
                browserStore: browserStore,
                historyStore: historyStore,
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                playerCoordinator: playerCoordinator,
                refreshesInitialMetadata: refreshesInitialMetadata
            )
        } else if initialItem.hasChildren {
            PlexMediaHierarchyView(
                initialItem: initialItem,
                browserStore: browserStore,
                historyStore: historyStore,
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                playerCoordinator: playerCoordinator,
                refreshesInitialMetadata: refreshesInitialMetadata
            )
        } else {
            PlexMediaDetailsView(
                initialItem: initialItem,
                browserStore: browserStore,
                historyStore: historyStore,
                settingsStore: settingsStore,
                connectionStore: connectionStore,
                playerCoordinator: playerCoordinator,
                refreshesInitialMetadata: refreshesInitialMetadata
            )
        }
    }
}

private struct PlexTVEpisodeDestinationView: View {
    let initialEpisode: PlexMediaItem
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var historyStore: PlexHistoryStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    let refreshesInitialMetadata: Bool
    @State private var show: PlexMediaItem?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let show {
                PlexTVShowDetailView(
                    initialShow: show,
                    initialEpisode: initialEpisode,
                    browserStore: browserStore,
                    historyStore: historyStore,
                    settingsStore: settingsStore,
                    connectionStore: connectionStore,
                    playerCoordinator: playerCoordinator,
                    refreshesInitialMetadata: refreshesInitialMetadata
                )
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Show", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else {
                ProgressView("Loading show…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: initialEpisode.ratingKey) {
            await resolveShow()
        }
    }

    private func resolveShow() async {
        guard let ratingKey = initialEpisode.grandparentRatingKey?.nilIfBlank,
              let route = PlexMediaRoute(ratingKey: ratingKey) else {
            errorMessage = "Plex did not identify the show for this episode."
            return
        }

        do {
            let resolvedShow = try await browserStore.resolveItem(for: route)
            guard !Task.isCancelled else { return }
            show = resolvedShow
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct PlexMediaHierarchyView: View {
    @Environment(PlexDownloadsStore.self) private var downloadsStore
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var historyStore: PlexHistoryStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    let refreshesInitialMetadata: Bool
    @State private var item: PlexMediaItem
    @State private var hierarchyItem: PlexMediaItem
    @State private var isPreparingPlayback = false
    @State private var playbackErrorMessage: String?
    @State private var presentsAutomaticDownload = false

    init(
        initialItem: PlexMediaItem,
        browserStore: PlexBrowserStore,
        historyStore: PlexHistoryStore,
        settingsStore: PlexSettingsStore,
        connectionStore: PlexConnectionStore,
        playerCoordinator: PlexPlayerCoordinator,
        refreshesInitialMetadata: Bool
    ) {
        self.browserStore = browserStore
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        self.connectionStore = connectionStore
        self.playerCoordinator = playerCoordinator
        self.refreshesInitialMetadata = refreshesInitialMetadata
        _item = State(initialValue: initialItem)
        _hierarchyItem = State(initialValue: initialItem)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            detailBackdrop
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PlexMediaOverview(
                        item: item,
                        settingsStore: settingsStore,
                        serverURL: connectionStore.resolvedServerURL,
                        showsPlaybackControl: hierarchyItem.continuousPlayQueueUsesOnDeck,
                        isPlaybackEnabled: hierarchyItem.supportsHierarchyPlayback,
                        isPreparingPlayback: isPreparingPlayback,
                        preparePlayback: preparePlayback,
                        showsAutomaticDownloadControl: downloadsStore
                            .canCreateAutomaticDownloadRule(for: item),
                        prepareAutomaticDownload: {
                            presentsAutomaticDownload = true
                        }
                    )

                    VStack(alignment: .leading, spacing: 30) {
                        childrenSection

                        PlexCastAndCrewView(
                            item: item,
                            settingsStore: settingsStore,
                            connectionStore: connectionStore
                        )

                        PlexMediaMetadataView(item: item)
                            .frame(maxWidth: 980, alignment: .leading)

                        if hasVisibleMediaHistory {
                            PlexMediaHistoryView(
                                item: item,
                                historyStore: historyStore,
                                settingsStore: settingsStore,
                                serverURL: connectionStore.resolvedServerURL
                            )
                        }

                        if hasVisibleExtras {
                            PlexMediaExtrasView(
                                item: item,
                                browserStore: browserStore,
                                settingsStore: settingsStore,
                                connectionStore: connectionStore,
                                playerCoordinator: playerCoordinator
                            )
                        }

                        if hasVisibleRelatedContent {
                            PlexRelatedContentView(
                                item: item,
                                browserStore: browserStore,
                                settingsStore: settingsStore,
                                connectionStore: connectionStore,
                                playerCoordinator: playerCoordinator
                            )
                        }
                    }
                    .frame(maxWidth: 1_100, alignment: .leading)
                    .scenePadding()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(item.title)
        .focusedSceneValue(
            \.plexRefreshCommand,
            PlexFocusedCommandAction(
                title: "Reload \(item.title)",
                isEnabled: !isReloadingContent,
                perform: refresh
            )
        )
        .task(id: item.id) {
            let requestedItem = item
            async let capabilityLoad: Void = browserStore.loadLibraryProviderCapabilities()
            async let discoveryLoad: Void = loadDiscoveryContent(for: requestedItem)
            async let historyLoad: Void = historyStore.loadMediaHistory(for: requestedItem)
            if refreshesInitialMetadata, item.supportsLibraryMetadataDetails {
                let details = await browserStore.details(for: item)
                if details != item {
                    hierarchyItem = hierarchyItem.hierarchyRequestItem(afterRefreshingWith: details)
                    item = details
                }
            }
            await browserStore.loadChildren(of: hierarchyItem)
            _ = await (capabilityLoad, discoveryLoad, historyLoad)
        }
        .toolbar {
            ToolbarItemGroup {
                PlexWatchedStateButton(item: $item, browserStore: browserStore)
                PlexPersonalRatingMenu(item: $item, browserStore: browserStore)
                PlexPlaybackQueueMenu(item: item, playerCoordinator: playerCoordinator)
                PlexMetadataRefreshButton(item: item, browserStore: browserStore)
                Button("Reload \(item.title)", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(isReloadingContent)
            }
        }
        .sheet(isPresented: $presentsAutomaticDownload) {
            PlexAutomaticDownloadSheet(item: item, downloadsStore: downloadsStore)
        }
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { playbackErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        playbackErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(playbackErrorMessage ?? "Unknown playback error.")
        }
    }

    @ViewBuilder
    private var detailBackdrop: some View {
        if item.usesCinematicHierarchyHero {
            Color(nsColor: .windowBackgroundColor)
        } else {
            PlexArtworkBackdrop(
                primaryImageURL: backdropPosterURL,
                token: settingsStore.trimmedServerToken,
                clientContext: clientContext
            )
        }
    }

    private var children: [PlexMediaItem] {
        browserStore.children(of: hierarchyItem)
    }

    private var hasVisibleMediaHistory: Bool {
        historyStore.mediaHistoryPresentation(for: item)?.isVisible == true
    }

    private var hasVisibleExtras: Bool {
        item.supportsLibraryMetadataDetails
            && (browserStore.isLoadingMediaExtras(for: item)
                || browserStore.mediaExtrasErrorMessage(for: item) != nil
                || !browserStore.mediaExtras(for: item).isEmpty)
    }

    private var hasVisibleRelatedContent: Bool {
        item.supportsLibraryMetadataDetails
            && (browserStore.isLoadingRelatedContent(for: item)
                || browserStore.relatedContentErrorMessage(for: item) != nil
                || !browserStore.relatedHubs(for: item).isEmpty)
    }

    private var isReloadingContent: Bool {
        browserStore.isLoadingChildren(of: hierarchyItem)
            || browserStore.detailDiscoveryPresentation(for: item).isLoading
            || historyStore.mediaHistoryPresentation(for: item)?.isLoading == true
    }

    private var backdropPosterURL: URL? {
        guard let serverURL = connectionStore.resolvedServerURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(
            serverURL: serverURL,
            path: item.art?.nilIfBlank ?? item.posterArtworkPath
        )
    }

    private var clientContext: PlexClientContext {
        PlexClientContext(clientIdentifier: settingsStore.clientIdentifier)
    }

    private var childrenSectionTitle: String {
        switch hierarchyItem.type?.lowercased() {
        case "show":
            hierarchyItem.skipChildren == true ? "Episodes" : "Seasons"
        case "season":
            "Episodes"
        case "artist":
            "Albums"
        case "album":
            "Tracks"
        case "photoalbum":
            "Photos"
        case "playlistfolder":
            "Playlists"
        default:
            "Items"
        }
    }

    private func refresh() {
        Task {
            let requestedItem = item
            async let childrenLoad: Void = browserStore.loadChildren(
                of: hierarchyItem,
                forceRefresh: true
            )
            async let discoveryLoad: Void = loadDiscoveryContent(
                for: requestedItem,
                forceRefresh: true
            )
            async let historyLoad: Void = historyStore.loadMediaHistory(
                for: requestedItem,
                forceRefresh: true
            )
            _ = await (childrenLoad, discoveryLoad, historyLoad)
        }
    }

    private func preparePlayback() {
        guard hierarchyItem.supportsHierarchyPlayback, !isPreparingPlayback else {
            return
        }

        isPreparingPlayback = true
        Task {
            defer { isPreparingPlayback = false }

            do {
                let queue = try await browserStore.continuousPlayQueue(for: hierarchyItem)
                let selectedItem = try await browserStore.refreshedPlayableDetails(
                    for: queue.currentItem
                )
                guard selectedItem.defaultPlaybackSource != nil else {
                    throw PlexAPIError.noPlayableMedia
                }

                let videoQuality = settingsStore.videoQuality(for: activeConnectionKind)
                let plan = try await browserStore.playbackPlan(
                    for: selectedItem,
                    videoQuality: videoQuality
                )
                playerCoordinator.present(PlexPlaybackPresentation(
                    item: selectedItem,
                    plan: plan,
                    queue: queue,
                    videoQuality: videoQuality,
                    serverIdentifier: connectionStore.activeConnection?.serverID
                        ?? settingsStore.selectedServerIdentifier?.nilIfBlank
                ))
            } catch {
                playbackErrorMessage = error.localizedDescription
            }
        }
    }

    private var activeConnectionKind: PlexConnectionKind? {
        connectionStore.activeConnection?.kind ?? settingsStore.cachedConnectionKind
    }

    @ViewBuilder
    private var childrenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(childrenSectionTitle)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 12)

                if !children.isEmpty {
                    Text(children.count, format: .number)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                if hierarchyItem.childrenPath == nil {
                    compactUnavailableContent(
                        title: "\(childrenSectionTitle) Unavailable",
                        message: "Plex did not provide a path for this item.",
                        symbol: "rectangle.stack.badge.exclamationmark",
                        retry: nil
                    )
                } else if browserStore.isLoadingChildren(of: hierarchyItem) && children.isEmpty {
                    ProgressView("Loading \(childrenSectionTitle)…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityLabel("Loading \(childrenSectionTitle)")
                } else if let errorMessage = browserStore.childrenErrorMessage(for: hierarchyItem), children.isEmpty {
                    compactUnavailableContent(
                        title: "Couldn’t Load \(childrenSectionTitle)",
                        message: errorMessage,
                        symbol: "exclamationmark.triangle",
                        retry: refresh
                    )
                } else if children.isEmpty {
                    compactUnavailableContent(
                        title: "No \(childrenSectionTitle)",
                        message: nil,
                        symbol: "rectangle.stack",
                        retry: nil
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                            NavigationLink(value: PlexNavigationRoute.media(PlexMediaRoute(item: child))) {
                                PlexMediaChildRow(
                                    item: child,
                                    settingsStore: settingsStore,
                                    serverURL: connectionStore.resolvedServerURL
                                )
                            }
                            .buttonStyle(.plain)
                            .plexMediaContextMenu(
                                for: child,
                                in: item,
                                browserStore: browserStore,
                                playerCoordinator: playerCoordinator
                            )
                            .task {
                                await browserStore.loadMoreChildrenIfNeeded(
                                    of: hierarchyItem,
                                    currentItem: child
                                )
                            }

                            if index < children.count - 1 {
                                Divider()
                            }
                        }

                        if browserStore.isLoadingChildren(of: hierarchyItem) {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .accessibilityLabel("Loading more \(childrenSectionTitle)")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    private func compactUnavailableContent(
        title: String,
        message: String?,
        symbol: String,
        retry: (() -> Void)?
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 160)
    }

    private func loadDiscoveryContent(
        for item: PlexMediaItem,
        forceRefresh: Bool = false
    ) async {
        guard item.supportsLibraryMetadataDetails else {
            return
        }
        await browserStore.loadDetailDiscoveryContent(
            for: item,
            forceRefresh: forceRefresh
        )
    }
}

struct PlexMediaOverview: View {
    let item: PlexMediaItem
    let settingsStore: PlexSettingsStore
    let serverURL: URL?
    let showsPlaybackControl: Bool
    let isPlaybackEnabled: Bool
    let isPreparingPlayback: Bool
    let preparePlayback: () -> Void
    let showsAutomaticDownloadControl: Bool
    let prepareAutomaticDownload: () -> Void
    @ScaledMetric(relativeTo: .body) private var artworkWidth: CGFloat = 120
    @ScaledMetric(relativeTo: .body) private var posterArtworkHeight: CGFloat = 180

    @ViewBuilder
    var body: some View {
        if item.usesCinematicHierarchyHero {
            cinematicOverview
        } else {
            compactOverview
                .scenePadding([.horizontal, .top])
        }
    }

    private var cinematicOverview: some View {
        PlexCinematicHero(
            primaryImageURL: heroArtworkURL,
            fallbackImageURL: artworkURL,
            token: settingsStore.trimmedServerToken,
            clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
            placeholderSymbol: item.placeholderSymbol
        ) {
            HStack(alignment: .bottom, spacing: 44) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 42, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .accessibilityAddTraits(.isHeader)

                        if !item.hierarchyDestinations.isEmpty {
                            PlexMediaHierarchyBreadcrumbs(destinations: item.hierarchyDestinations)
                        }

                        PlexMediaFactsView(
                            presentation: item.factsPresentation,
                            genres: PlexMediaSummaryPresentation(item: item).genres
                        )
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            if showsPlaybackControl {
                                Button(action: preparePlayback) {
                                    if isPreparingPlayback {
                                        ProgressView()
                                            .controlSize(.small)
                                } else {
                                    Label("Play", systemImage: "play.fill")
                                }
                            }
                                .frame(width: 216)
                                .plexCinematicPrimaryButton()
                                .disabled(!isPlaybackEnabled || isPreparingPlayback)
                                .accessibilityLabel(
                                    isPreparingPlayback ? "Preparing \(item.title)" : "Play \(item.title)"
                                )
                            }

                            if showsAutomaticDownloadControl {
                                Button(
                                    "Download",
                                    systemImage: "arrow.down.circle",
                                    action: prepareAutomaticDownload
                                )
                                .labelStyle(.iconOnly)
                                .plexCinematicUtilityButton()
                            }
                        }
                    }
                }
                .frame(maxWidth: 460, alignment: .leading)

                if let summary = item.summary?.nilIfBlank {
                    PlexMediaDescriptionView(title: item.title, summary: summary)
                        .frame(maxWidth: 560, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }

    private var compactOverview: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 0) {
            GridRow(alignment: .top) {
                PlexArtworkView(
                    primaryImageURL: artworkURL,
                    fallbackImageURL: nil,
                    token: settingsStore.trimmedServerToken,
                    clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                    placeholderSymbol: item.placeholderSymbol,
                    width: artworkWidth,
                    height: item.usesSquareArtwork ? artworkWidth : posterArtworkHeight,
                    cornerRadius: 10
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.title)
                        .fontWeight(.semibold)
                        .accessibilityAddTraits(.isHeader)

                    if !item.hierarchyDestinations.isEmpty {
                        PlexMediaHierarchyBreadcrumbs(destinations: item.hierarchyDestinations)
                    }

                    PlexMediaFactsView(presentation: item.factsPresentation)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        if showsPlaybackControl {
                            Button(action: preparePlayback) {
                                if isPreparingPlayback {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Play", systemImage: "play.fill")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isPlaybackEnabled || isPreparingPlayback)
                            .accessibilityLabel(
                                isPreparingPlayback ? "Preparing \(item.title)" : "Play \(item.title)"
                            )
                        }

                        if showsAutomaticDownloadControl {
                            Button(
                                "Download",
                                systemImage: "arrow.down.circle",
                                action: prepareAutomaticDownload
                            )
                            .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.large)

                    if let summary = item.summary?.nilIfBlank {
                        PlexMediaDescriptionView(title: item.title, summary: summary)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private var heroArtworkURL: URL? {
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: item.art?.nilIfBlank)
    }

    private var artworkURL: URL? {
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: item.preferredArtworkPath)
    }
}

struct PlexMediaChildRow: View {
    let item: PlexMediaItem
    let settingsStore: PlexSettingsStore
    let serverURL: URL?
    @ScaledMetric(relativeTo: .body) private var compactArtworkSize: CGFloat = 54
    @ScaledMetric(relativeTo: .body) private var posterArtworkWidth: CGFloat = 54
    @ScaledMetric(relativeTo: .body) private var posterArtworkHeight: CGFloat = 81
    @ScaledMetric(relativeTo: .body) private var episodeArtworkWidth: CGFloat = 128
    @ScaledMetric(relativeTo: .body) private var episodeArtworkHeight: CGFloat = 72

    var body: some View {
        HStack(spacing: 14) {
            PlexArtworkView(
                primaryImageURL: artworkURL,
                fallbackImageURL: fallbackArtworkURL,
                token: settingsStore.trimmedServerToken,
                clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                placeholderSymbol: spoilerPresentation.isProtected ? "eye.slash" : item.placeholderSymbol,
                width: artworkWidth,
                height: artworkHeight,
                cornerRadius: 6
            )
            .plexWatchedIndicator(isWatched: item.isWatched, scale: .compact)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)

                if let subtitle = rowSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let summary = spoilerPresentation.summary, item.type?.lowercased() == "episode" {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let progress = item.progress {
                    ProgressView(value: progress)
                        .frame(maxWidth: 220)
                        .accessibilityHidden(true)
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.watchStateAccessibilityValue ?? "")
    }

    private var artworkURL: URL? {
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: spoilerPresentation.thumbnailPath)
    }

    private var fallbackArtworkURL: URL? {
        guard !spoilerPresentation.isProtected else {
            return nil
        }
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(
            serverURL: serverURL,
            path: item.parentThumb ?? item.grandparentThumb
        )
    }

    private var spoilerPresentation: PlexEpisodeSpoilerPresentation {
        PlexEpisodeSpoilerPresentation(
            item: item,
            policy: settingsStore.episodeSpoilerPolicy
        )
    }

    private var artworkWidth: CGFloat {
        switch item.type?.lowercased() {
        case "episode", "clip": episodeArtworkWidth
        case "season": posterArtworkWidth
        default: compactArtworkSize
        }
    }

    private var artworkHeight: CGFloat {
        switch item.type?.lowercased() {
        case "episode", "clip": episodeArtworkHeight
        case "season": posterArtworkHeight
        default: compactArtworkSize
        }
    }

    private var rowSubtitle: String? {
        switch item.type?.lowercased() {
        case "season":
            item.leafCount.map { "\($0.formatted()) \($0 == 1 ? "episode" : "episodes")" }
        case "episode":
            [item.episodeIdentifier, item.formattedDuration].compactMap { $0 }.joined(separator: " · ").nilIfBlank
        case "album":
            item.year.map(String.init)
        case "track":
            [item.index.map { "Track \($0)" }, item.formattedDuration]
                .compactMap { $0 }
                .joined(separator: " · ")
                .nilIfBlank
        case "collection", "playlist", "playlistfolder":
            [item.itemCountLabel, item.formattedDuration]
                .compactMap { $0 }
                .joined(separator: " · ")
                .nilIfBlank
        default:
            item.subtitle
        }
    }
}

private extension PlexMediaItem {
    var supportsLibraryMetadataDetails: Bool {
        guard let type = type?.lowercased() else {
            return true
        }
        return type != "collection" && type != "playlist" && type != "playlistfolder"
    }
}
