import SwiftUI

struct PlexTVShowDetailView: View {
    @Environment(PlexDownloadsStore.self) private var downloadsStore
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var historyStore: PlexHistoryStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    let refreshesInitialMetadata: Bool
    @State private var show: PlexMediaItem
    @State private var hierarchyShow: PlexMediaItem
    @State private var selectedSeasonID: String?
    @State private var selectedEpisode: PlexMediaItem?
    @State private var episodeSeriesCast: [PlexTag] = []
    @State private var isPreparingPlayback = false
    @State private var isLoadingEpisode = false
    @State private var playbackErrorMessage: String?
    @State private var downloadErrorMessage: String?

    init(
        initialShow: PlexMediaItem,
        initialEpisode: PlexMediaItem? = nil,
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
        _show = State(initialValue: initialShow)
        _hierarchyShow = State(initialValue: initialShow)
        _selectedEpisode = State(initialValue: initialEpisode)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    showHero

                    VStack(alignment: .leading, spacing: 30) {
                        episodeBrowser

                        if let selectedEpisode {
                            PlexCastAndCrewView(
                                item: selectedEpisode,
                                episodeSeriesCast: episodeSeriesCast,
                                settingsStore: settingsStore,
                                connectionStore: connectionStore
                            )

                            PlexMediaMetadataView(item: selectedEpisode)
                                .frame(maxWidth: 980, alignment: .leading)
                        } else {
                            PlexCastAndCrewView(
                                item: show,
                                settingsStore: settingsStore,
                                connectionStore: connectionStore
                            )

                            PlexMediaMetadataView(item: show)
                                .frame(maxWidth: 980, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: 1_180, alignment: .leading)
                    .scenePadding()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(show.title)
        .focusedSceneValue(
            \.plexRefreshCommand,
            PlexFocusedCommandAction(
                title: "Reload \(show.title)",
                isEnabled: !isReloading,
                perform: refresh
            )
        )
        .task(id: show.ratingKey) {
            await loadShow()
        }
        .task(id: selectedSeasonID) {
            await loadSelectedSeason()
        }
        .toolbar {
            ToolbarItem {
                Button("Reload \(show.title)", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(isReloading)
            }
        }
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { playbackErrorMessage != nil },
                set: { if !$0 { playbackErrorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(playbackErrorMessage ?? "Unknown playback error.")
        }
        .alert(
            "Download Error",
            isPresented: Binding(
                get: { downloadErrorMessage != nil },
                set: { if !$0 { downloadErrorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(downloadErrorMessage ?? "Unknown download error.")
        }
    }

    private var showHero: some View {
        PlexCinematicMediaHero(
            primaryImageURL: heroArtworkURL,
            fallbackImageURL: posterURL,
            clearLogoURL: clearLogoURL,
            title: show.title,
            logoAccessibilityLabel: show.images.first {
                $0.type.caseInsensitiveCompare("clearLogo") == .orderedSame
            }?.alt,
            token: settingsStore.trimmedServerToken,
            clientContext: clientContext,
            placeholderSymbol: show.placeholderSymbol,
            playbackTitle: selectedEpisode?.title,
            ratingsItem: show,
            hasResumePosition: selectedEpisode?.hasResumePosition == true,
            resumeProgress: selectedEpisode?.progress,
            isPreparingPlayback: isPreparingPlayback,
            isPlaybackEnabled: selectedEpisode?.defaultPlaybackSource != nil,
            preparePlayback: preparePlayback
        ) {
            if let selectedEpisode {
                episodeActions(for: selectedEpisode)
            }
        } details: {
            episodeSummary
        }
    }

    @ViewBuilder
    private var episodeSummary: some View {
        if let selectedEpisode {
            VStack(alignment: .leading, spacing: 10) {
                Text(episodeHeading(selectedEpisode))
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)

                if let facts = episodeFacts(selectedEpisode) {
                    Text(facts)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }

                if let summary = PlexEpisodeSpoilerPresentation(
                    item: selectedEpisode,
                    policy: settingsStore.episodeSpoilerPolicy
                ).summary {
                    Text(summary)
                        .font(.body)
                        .lineSpacing(3)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }

            }
        } else if isLoadingEpisode || browserStore.isLoadingChildren(of: hierarchyShow) {
            ProgressView("Loading episodes…")
                .tint(.white)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No Episodes")
                    .font(.title2.weight(.semibold))
                Text("Plex did not return any episodes for this show.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func episodeActions(for episode: PlexMediaItem) -> some View {
        let binding = Binding(
            get: { selectedEpisode ?? episode },
            set: { selectedEpisode = $0 }
        )

        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                PlexWatchedStateButton(item: binding, browserStore: browserStore)
                    .plexCinematicUtilityButton()

                if showsDownloadControl(for: episode) {
                    downloadButton(for: episode)
                        .plexCinematicUtilityButton()
                }

                PlexPersonalRatingMenu(item: binding, browserStore: browserStore)
                    .plexCinematicUtilityButton()
            }
            .labelStyle(.iconOnly)
        }
    }

    private var episodeBrowser: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if seasons.isEmpty {
                    Text("Episodes")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Menu {
                        ForEach(seasons) { season in
                            Button {
                                selectedSeasonID = season.id
                            } label: {
                                if season.id == selectedSeasonID {
                                    Label(season.title, systemImage: "checkmark")
                                } else {
                                    Text(season.title)
                                }
                            }
                        }
                    } label: {
                        Text(selectedSeason?.title ?? "Season")
                            .font(.title2.weight(.semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Season")
                    .accessibilityValue(selectedSeason?.title ?? "No season selected")
                }
            }

            if isLoadingEpisode && episodes.isEmpty {
                ProgressView("Loading episodes…")
                    .frame(maxWidth: .infinity, minHeight: 145)
            } else if episodes.isEmpty {
                ContentUnavailableView("No Episodes", systemImage: "tv")
                    .frame(maxWidth: .infinity, minHeight: 145)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(episodes) { episode in
                            episodeButton(episode)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private func episodeButton(_ episode: PlexMediaItem) -> some View {
        let isSelected = selectedEpisode?.ratingKey == episode.ratingKey
        let spoiler = PlexEpisodeSpoilerPresentation(
            item: episode,
            policy: settingsStore.episodeSpoilerPolicy
        )

        return Button {
            Task { await selectEpisode(episode) }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                PlexArtworkView(
                    primaryImageURL: mediaURL(path: spoiler.thumbnailPath),
                    fallbackImageURL: spoiler.isProtected ? nil : posterURL,
                    token: settingsStore.trimmedServerToken,
                    clientContext: clientContext,
                    placeholderSymbol: spoiler.isProtected ? "eye.slash" : episode.placeholderSymbol,
                    width: 208,
                    height: 117,
                    cornerRadius: 10
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
                .overlay(alignment: .bottomLeading) {
                    if let progress = episode.progress {
                        ProgressView(value: progress)
                            .tint(.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.bottom, 5)
                            .accessibilityHidden(true)
                    }
                }
                .plexWatchedIndicator(isWatched: episode.isWatched)

                Text(episodeCardTitle(episode))
                    .font(.headline)
                    .lineLimit(1)

                if let duration = episode.formattedDuration {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 208, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(episodeHeading(episode))
        .accessibilityValue(episode.watchStateAccessibilityValue ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func downloadButton(for episode: PlexMediaItem) -> some View {
        if downloadsStore.containsDownload(for: episode) {
            Button("Downloaded", systemImage: "checkmark.circle.fill") {}
                .disabled(true)
        } else if downloadsStore.isDownloading(episode) {
            Button("Downloading", systemImage: "arrow.down.circle") {}
                .disabled(true)
        } else {
            Button("Download", systemImage: "arrow.down.circle") {
                prepareDownload(episode)
            }
            .disabled(episode.defaultPlaybackSource == nil)
        }
    }

    private var seasons: [PlexMediaItem] {
        browserStore.children(of: hierarchyShow).filter { $0.type?.lowercased() == "season" }
    }

    private var selectedSeason: PlexMediaItem? {
        seasons.first { $0.id == selectedSeasonID }
    }

    private var episodes: [PlexMediaItem] {
        if let selectedSeason {
            return browserStore.children(of: selectedSeason).filter {
                $0.type?.lowercased() == "episode"
            }
        }
        return browserStore.children(of: hierarchyShow).filter {
            $0.type?.lowercased() == "episode"
        }
    }

    private var isReloading: Bool {
        browserStore.isLoadingChildren(of: hierarchyShow) || isLoadingEpisode
    }

    private var clientContext: PlexClientContext {
        PlexClientContext(clientIdentifier: settingsStore.clientIdentifier)
    }

    private var activeConnectionKind: PlexConnectionKind? {
        connectionStore.activeConnection?.kind ?? settingsStore.cachedConnectionKind
    }

    private var heroArtworkURL: URL? {
        mediaURL(path: show.art?.nilIfBlank)
    }

    private var posterURL: URL? {
        mediaURL(path: show.posterArtworkPath)
    }

    private var clearLogoURL: URL? {
        mediaURL(path: show.clearLogoPath)
    }

    private func mediaURL(path: String?) -> URL? {
        guard let serverURL = connectionStore.resolvedServerURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: path)
    }

    private func episodeHeading(_ episode: PlexMediaItem) -> String {
        [episode.episodeIdentifier, episode.title]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " — ")
    }

    private func episodeCardTitle(_ episode: PlexMediaItem) -> String {
        if let index = episode.index {
            return "\(index). \(episode.title)"
        }
        return episode.title
    }

    private func episodeFacts(_ episode: PlexMediaItem) -> String? {
        [
            episode.formattedDuration,
            PlexMediaMetadataPresentation(item: episode).facts.first {
                $0.kind == .releaseDate
            }?.value,
            episode.contentRating?.nilIfBlank,
        ]
        .compactMap { $0 }
        .joined(separator: "  ·  ")
        .nilIfBlank
    }

    private func showsDownloadControl(for episode: PlexMediaItem) -> Bool {
        downloadsStore.containsDownload(for: episode)
            || downloadsStore.isDownloading(episode)
            || downloadsStore.canCreateDownload(for: episode)
    }

    private func loadShow(forceRefresh: Bool = false) async {
        async let capabilityLoad: Void = browserStore.loadLibraryProviderCapabilities()

        if refreshesInitialMetadata || forceRefresh {
            let details = await browserStore.details(for: show)
            guard !Task.isCancelled else { return }
            hierarchyShow = hierarchyShow.hierarchyRequestItem(afterRefreshingWith: details)
            show = details
        }

        await browserStore.loadChildren(of: hierarchyShow, forceRefresh: forceRefresh)
        guard !Task.isCancelled else { return }

        if seasons.isEmpty {
            selectedSeasonID = nil
            if selectedEpisode == nil || forceRefresh {
                await selectEpisode(episodes.first)
            }
        } else if selectedSeasonID == nil || !seasons.contains(where: { $0.id == selectedSeasonID }) {
            selectedSeasonID = seasons.first {
                $0.ratingKey == selectedEpisode?.parentRatingKey
            }?.id ?? seasons.first?.id
        } else if forceRefresh, let selectedSeason {
            await browserStore.loadChildren(of: selectedSeason, forceRefresh: true)
            let refreshedEpisodes = browserStore.children(of: selectedSeason).filter {
                $0.type?.lowercased() == "episode"
            }
            let episode = refreshedEpisodes.first {
                $0.ratingKey == selectedEpisode?.ratingKey
            } ?? refreshedEpisodes.first
            await selectEpisode(episode)
        }

        _ = await capabilityLoad
    }

    private func loadSelectedSeason() async {
        guard let selectedSeason else {
            return
        }
        isLoadingEpisode = true
        defer { isLoadingEpisode = false }

        await browserStore.loadChildren(of: selectedSeason)
        guard self.selectedSeason?.id == selectedSeason.id, !Task.isCancelled else {
            return
        }

        let seasonEpisodes = browserStore.children(of: selectedSeason).filter {
            $0.type?.lowercased() == "episode"
        }
        let episode = seasonEpisodes.first {
            $0.ratingKey == selectedEpisode?.ratingKey
        } ?? seasonEpisodes.first
        await selectEpisode(episode)
    }

    private func selectEpisode(_ episode: PlexMediaItem?) async {
        guard let episode else {
            selectedEpisode = nil
            episodeSeriesCast = []
            return
        }

        selectedEpisode = episode
        isLoadingEpisode = true
        let requestedRatingKey = episode.ratingKey
        async let detailLoad = browserStore.details(for: episode)
        async let castLoad = browserStore.episodeSeriesCast(for: episode)
        let (details, cast) = await (detailLoad, castLoad)
        guard selectedEpisode?.ratingKey == requestedRatingKey, !Task.isCancelled else {
            return
        }
        selectedEpisode = details
        episodeSeriesCast = cast
        isLoadingEpisode = false
    }

    private func refresh() {
        guard !isReloading else { return }
        Task { await loadShow(forceRefresh: true) }
    }

    private func preparePlayback(_ startOption: PlexPlaybackStartOption) {
        guard let episode = selectedEpisode, !isPreparingPlayback else {
            return
        }
        isPreparingPlayback = true
        Task {
            defer { isPreparingPlayback = false }
            do {
                let playbackItem = try await browserStore.refreshedPlayableDetails(for: episode)
                guard let source = playbackItem.defaultPlaybackSource else {
                    throw PlexAPIError.noPlayableMedia
                }
                let videoQuality = settingsStore.videoQuality(for: activeConnectionKind)
                async let plan = browserStore.playbackPlan(
                    for: playbackItem,
                    source: source,
                    videoQuality: videoQuality,
                    startTimeOverride: startOption.startTimeOverride
                )
                async let queue = browserStore.continuousPlayQueue(for: playbackItem)
                let presentation = try await PlexPlaybackPresentation(
                    item: playbackItem,
                    plan: plan,
                    queue: queue,
                    videoQuality: videoQuality,
                    serverIdentifier: connectionStore.activeConnection?.serverID
                        ?? settingsStore.selectedServerIdentifier?.nilIfBlank
                )
                playerCoordinator.present(presentation)
            } catch {
                playbackErrorMessage = error.localizedDescription
            }
        }
    }

    private func prepareDownload(_ episode: PlexMediaItem) {
        guard let source = episode.defaultPlaybackSource else { return }
        Task {
            do {
                try await downloadsStore.download(episode, source: source)
            } catch {
                downloadErrorMessage = error.localizedDescription
            }
        }
    }
}
