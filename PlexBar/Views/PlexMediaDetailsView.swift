import SwiftUI

struct PlexMediaDetailsView: View {
    @Environment(PlexDownloadsStore.self) private var downloadsStore
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var historyStore: PlexHistoryStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    let refreshesInitialMetadata: Bool
    @State private var item: PlexMediaItem
    @State private var selectedMediaIndex: Int
    @State private var isPreparingPlayback = false
    @State private var isPreparingPrimaryExtra = false
    @State private var isReloadingDetails = false
    @State private var episodeSeriesCast: [PlexTag] = []
    @State private var playbackErrorMessage: String?
    @State private var downloadErrorMessage: String?

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
        _selectedMediaIndex = State(initialValue: initialItem.defaultPlaybackSource?.mediaIndex ?? 0)
    }

    var body: some View {
        ZStack {
            detailBackdrop
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    mediaHeader

                    VStack(alignment: .leading, spacing: 30) {
                        PlexCastAndCrewView(
                            item: item,
                            episodeSeriesCast: episodeSeriesCast,
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
                    .frame(maxWidth: 1_180, alignment: .leading)
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
                perform: reloadDetails
            )
        )
        .task(id: item.ratingKey) {
            episodeSeriesCast = []
            let requestedItem = item
            async let capabilityLoad: Void = browserStore.loadLibraryProviderCapabilities()
            async let discoveryLoad: Void = browserStore.loadDetailDiscoveryContent(for: requestedItem)
            async let historyLoad: Void = historyStore.loadMediaHistory(for: requestedItem)
            await loadInitialDetailsIfNeeded()
            await loadEpisodeSeriesCast()
            _ = await (capabilityLoad, discoveryLoad, historyLoad)
        }
        .toolbar {
            ToolbarItem {
                PlexMetadataRefreshButton(item: item, browserStore: browserStore)
            }
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

    @ViewBuilder
    private var detailBackdrop: some View {
        if item.usesCinematicDetailHero {
            Color(nsColor: .windowBackgroundColor)
        } else {
            PlexArtworkBackdrop(
                primaryImageURL: backdropPosterURL,
                fallbackImageURL: backdropFallbackPosterURL,
                token: settingsStore.trimmedServerToken,
                clientContext: clientContext
            )
        }
    }

    private var hasVisibleMediaHistory: Bool {
        historyStore.mediaHistoryPresentation(for: item)?.isVisible == true
    }

    private var hasVisibleExtras: Bool {
        browserStore.isLoadingMediaExtras(for: item)
            || browserStore.mediaExtrasErrorMessage(for: item) != nil
            || !browserStore.mediaExtras(for: item).isEmpty
    }

    private var hasVisibleRelatedContent: Bool {
        browserStore.isLoadingRelatedContent(for: item)
            || browserStore.relatedContentErrorMessage(for: item) != nil
            || !browserStore.relatedHubs(for: item).isEmpty
    }

    @ViewBuilder
    private var mediaHeader: some View {
        if let photoPresentation = PlexPhotoPresentation(item: item) {
            photoHeader(photoPresentation)
        } else {
            standardMediaHeader
        }
    }

    private func photoHeader(_ presentation: PlexPhotoPresentation) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            PlexPhotoDetailStage(
                presentation: presentation,
                title: item.title,
                serverURL: connectionStore.resolvedServerURL,
                token: settingsStore.trimmedServerToken,
                clientContext: clientContext
            )

            VStack(alignment: .leading, spacing: 18) {
                titleBlock

                if let tagline = item.tagline?.nilIfBlank {
                    Text(tagline)
                        .font(.title3)
                        .italic()
                        .foregroundStyle(.secondary)
                }

                if let summary = spoilerPresentation.summary {
                    Text(summary)
                        .font(.body)
                        .textSelection(.enabled)
                }

                PlexMediaMetadataView(item: item)
            }
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: 1_100, alignment: .leading)
    }

    @ViewBuilder
    private var standardMediaHeader: some View {
        if item.usesCinematicDetailHero {
            cinematicMediaHeader
        } else {
            compactMediaHeader
        }
    }

    private var cinematicMediaHeader: some View {
        PlexCinematicMediaHero(
            primaryImageURL: heroArtworkURL,
            fallbackImageURL: posterURL ?? detailFallbackArtworkURL,
            clearLogoURL: clearLogoURL,
            title: item.title,
            logoAccessibilityLabel: item.images.first {
                $0.type.caseInsensitiveCompare("clearLogo") == .orderedSame
            }?.alt,
            token: settingsStore.trimmedServerToken,
            clientContext: clientContext,
            placeholderSymbol: spoilerPresentation.isProtected ? "eye.slash" : item.placeholderSymbol,
            playbackTitle: item.title,
            ratingsItem: item,
            hasResumePosition: item.hasResumePosition,
            resumeProgress: item.progress,
            isPreparingPlayback: isPreparingPlayback,
            isPlaybackEnabled: selectedPlaybackSource != nil && !isPreparingPrimaryExtra,
            preparePlayback: preparePlayback
        ) {
            heroActions
        } details: {
            heroDescription
        }
    }

    private var compactMediaHeader: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 28, verticalSpacing: 0) {
            GridRow(alignment: .top) {
                PlexArtworkView(
                    primaryImageURL: posterURL,
                    fallbackImageURL: detailFallbackArtworkURL,
                    token: settingsStore.trimmedServerToken,
                    clientContext: clientContext,
                    placeholderSymbol: item.placeholderSymbol,
                    width: 220,
                    height: item.usesSquareArtwork ? 220 : 330,
                    cornerRadius: 16
                )

                VStack(alignment: .leading, spacing: 18) {
                    titleBlock

                    HStack(spacing: 10) {
                        PlexPlaybackStartControl(
                            title: item.title,
                            hasResumePosition: item.hasResumePosition,
                            resumeProgress: item.progress,
                            isPreparing: isPreparingPlayback,
                            isEnabled: selectedPlaybackSource != nil && !isPreparingPrimaryExtra,
                            action: preparePlayback
                        )
                        .fixedSize()

                        if showsDownloadControl {
                            downloadButton
                                .buttonStyle(.glass)
                        }

                        PlexPlaybackQueueMenu(
                            item: item,
                            playerCoordinator: playerCoordinator
                        )
                        .buttonStyle(.glass)
                    }
                    .controlSize(.large)

                    if playableMediaIndices.count > 1 {
                        Picker("Version", selection: $selectedMediaIndex) {
                            ForEach(playableMediaIndices, id: \.self) { mediaIndex in
                                Text(versionLabel(at: mediaIndex))
                                    .tag(mediaIndex)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }

                    if let summary = spoilerPresentation.summary {
                        Text(summary)
                            .lineLimit(8)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var heroActions: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if let primaryExtraTitle = item.primaryExtraActionTitle {
                        PlexPrimaryExtraButton(
                            title: primaryExtraTitle,
                            isPreparing: isPreparingPrimaryExtra,
                            isEnabled: !isPreparingPlayback,
                            action: preparePrimaryExtra
                        )
                        .plexCinematicUtilityButton()
                        .help("Play \(primaryExtraTitle)")
                    }

                    PlexWatchedStateButton(item: $item, browserStore: browserStore)
                        .plexCinematicUtilityButton()

                    if showsDownloadControl {
                        downloadButton
                            .plexCinematicUtilityButton()
                    }

                    PlexPersonalRatingMenu(item: $item, browserStore: browserStore)
                        .plexCinematicUtilityButton()

                    PlexPlaybackQueueMenu(
                        item: item,
                        playerCoordinator: playerCoordinator
                    )
                    .plexCinematicUtilityButton()
                }
                .labelStyle(.iconOnly)
            }

            if playableMediaIndices.count > 1 {
                Picker("Version", selection: $selectedMediaIndex) {
                    ForEach(playableMediaIndices, id: \.self) { mediaIndex in
                        Text(versionLabel(at: mediaIndex))
                            .tag(mediaIndex)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    private var heroDescription: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let factsLine = heroFactsLine {
                Text(factsLine)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }

            if let tagline = item.tagline?.nilIfBlank {
                Text(tagline)
                    .font(.title3)
                    .italic()
                    .foregroundStyle(.white.opacity(0.80))
            }

            if let summary = spoilerPresentation.summary {
                Text(summary)
                    .font(.body)
                    .lineSpacing(3)
                    .lineLimit(5)
                    .textSelection(.enabled)
            }

        }
    }

    private var heroFactsLine: String? {
        let genres = item.genres.prefix(3).map(\.tag).joined(separator: ", ").nilIfBlank
        return [item.factsLine, genres]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
            .nilIfBlank
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title)
                .font(.largeTitle)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)

            if !item.hierarchyDestinations.isEmpty {
                PlexMediaHierarchyBreadcrumbs(destinations: item.hierarchyDestinations)
            }

            if let factsLine = item.factsLine {
                Text(factsLine)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        if downloadsStore.containsDownload(for: item) {
            Button("Downloaded", systemImage: "checkmark.circle.fill") {}
                .disabled(true)
        } else if downloadsStore.isDownloading(item) {
            Button("Downloading", systemImage: "arrow.down.circle") {}
                .disabled(true)
        } else {
            Button("Download", systemImage: "arrow.down.circle", action: prepareDownload)
                .disabled(selectedPlaybackSource == nil)
        }
    }

    private var showsDownloadControl: Bool {
        downloadsStore.containsDownload(for: item)
            || downloadsStore.isDownloading(item)
            || downloadsStore.canCreateDownload(for: item)
    }

    private func prepareDownload() {
        guard let selectedPlaybackSource else { return }
        Task {
            do {
                try await downloadsStore.download(item, source: selectedPlaybackSource)
            } catch {
                downloadErrorMessage = error.localizedDescription
            }
        }
    }

    private var posterURL: URL? {
        guard let serverURL = connectionStore.resolvedServerURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: spoilerPresentation.thumbnailPath)
    }

    private var heroArtworkURL: URL? {
        guard let serverURL = connectionStore.resolvedServerURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: item.art?.nilIfBlank)
    }

    private var clearLogoURL: URL? {
        guard let serverURL = connectionStore.resolvedServerURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: item.clearLogoPath)
    }

    private func reloadDetails() {
        guard !isReloadingContent else {
            return
        }
        Task {
            let requestedItem = item
            async let discoveryLoad: Void = browserStore.loadDetailDiscoveryContent(
                for: requestedItem,
                forceRefresh: true
            )
            async let historyLoad: Void = historyStore.loadMediaHistory(
                for: requestedItem,
                forceRefresh: true
            )
            await loadDetails()
            await loadEpisodeSeriesCast()
            _ = await (discoveryLoad, historyLoad)
        }
    }

    private var isReloadingContent: Bool {
        isReloadingDetails
            || browserStore.detailDiscoveryPresentation(for: item).isLoading
            || historyStore.mediaHistoryPresentation(for: item)?.isLoading == true
    }

    private func loadDetails() async {
        guard !isReloadingDetails else {
            return
        }
        isReloadingDetails = true
        defer { isReloadingDetails = false }

        let details = await browserStore.details(for: item)
        if details != item {
            item = details
            selectedMediaIndex = details.defaultPlaybackSource?.mediaIndex ?? 0
        }
    }

    private func loadInitialDetailsIfNeeded() async {
        guard refreshesInitialMetadata else {
            return
        }
        await loadDetails()
    }

    private func loadEpisodeSeriesCast() async {
        let requestedRatingKey = item.ratingKey
        let cast = await browserStore.episodeSeriesCast(for: item)
        guard item.ratingKey == requestedRatingKey, !Task.isCancelled else {
            return
        }
        episodeSeriesCast = cast
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

    private var backdropFallbackPosterURL: URL? {
        guard let serverURL = connectionStore.resolvedServerURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(
            serverURL: serverURL,
            path: item.parentThumb ?? item.grandparentThumb
        )
    }

    private var detailFallbackArtworkURL: URL? {
        guard !spoilerPresentation.isProtected else {
            return nil
        }
        return backdropFallbackPosterURL
    }

    private var spoilerPresentation: PlexEpisodeSpoilerPresentation {
        PlexEpisodeSpoilerPresentation(
            item: item,
            policy: settingsStore.episodeSpoilerPolicy
        )
    }

    private var playableMediaIndices: [Int] {
        item.media.indices.filter { !item.media[$0].parts.isEmpty }
    }

    private var selectedPlaybackSource: PlexPlaybackSource? {
        item.playbackSource(mediaIndex: selectedMediaIndex)
    }

    private var activeConnectionKind: PlexConnectionKind? {
        connectionStore.activeConnection?.kind ?? settingsStore.cachedConnectionKind
    }

    private func versionLabel(at mediaIndex: Int) -> String {
        let version = item.media[mediaIndex]
        var facts: [String] = []

        if let width = version.width, let height = version.height {
            facts.append("\(width) × \(height)")
        } else if let resolution = version.videoResolution?.nilIfBlank {
            facts.append(resolution.uppercased())
        }
        if let videoCodec = version.videoCodec?.nilIfBlank {
            facts.append(videoCodec.uppercased())
        }
        if let bitrate = version.bitrate, bitrate > 0 {
            facts.append(formattedBitrate(bitrate))
        }
        if let container = version.container?.nilIfBlank {
            facts.append(container.uppercased())
        }

        let prefix = "\(mediaIndex + 1)"
        return facts.isEmpty ? prefix : "\(prefix) · \(facts.joined(separator: " · "))"
    }

    private func formattedBitrate(_ kilobitsPerSecond: Int) -> String {
        guard kilobitsPerSecond >= 1_000 else {
            return "\(kilobitsPerSecond) kbps"
        }

        let megabitsPerSecond = Double(kilobitsPerSecond) / 1_000
        return megabitsPerSecond.formatted(.number.precision(.fractionLength(0...1))) + " Mbps"
    }

    private func preparePlayback(_ startOption: PlexPlaybackStartOption) {
        guard !isPreparingPlayback, !isPreparingPrimaryExtra else {
            return
        }

        isPreparingPlayback = true
        Task {
            defer { isPreparingPlayback = false }

            do {
                let playbackItem = try await browserStore.refreshedPlayableDetails(for: item)
                let videoQuality = settingsStore.videoQuality(for: activeConnectionKind)
                let presentation = try await playbackPresentation(
                    for: playbackItem,
                    startOption: startOption,
                    videoQuality: videoQuality
                )
                playerCoordinator.present(presentation)
            } catch {
                playbackErrorMessage = error.localizedDescription
            }
        }
    }

    private func preparePrimaryExtra() {
        guard !isPreparingPlayback, !isPreparingPrimaryExtra else {
            return
        }

        isPreparingPrimaryExtra = true
        Task {
            defer { isPreparingPrimaryExtra = false }

            do {
                let extra = try await browserStore.primaryExtra(for: item)
                guard let source = extra.defaultPlaybackSource else {
                    throw PlexAPIError.noPlayableMedia
                }

                let videoQuality = settingsStore.videoQuality(for: activeConnectionKind)
                let plan = try await browserStore.playbackPlan(
                    for: extra,
                    source: source,
                    videoQuality: videoQuality,
                    startTimeOverride: 0
                )
                playerCoordinator.present(PlexPlaybackPresentation(
                    item: extra,
                    plan: plan,
                    queue: nil,
                    videoQuality: videoQuality,
                    serverIdentifier: connectionStore.activeConnection?.serverID
                        ?? settingsStore.selectedServerIdentifier?.nilIfBlank
                ))
            } catch {
                playbackErrorMessage = error.localizedDescription
            }
        }
    }

    private func playbackQueue(for item: PlexMediaItem) async throws -> PlexPlaybackQueue? {
        guard item.continuousPlayQueueType != nil else {
            return nil
        }
        return try await browserStore.continuousPlayQueue(for: item)
    }

    private func playbackPresentation(
        for playbackItem: PlexMediaItem,
        startOption: PlexPlaybackStartOption,
        videoQuality: PlexVideoQuality
    ) async throws -> PlexPlaybackPresentation {
        guard let selectedPlaybackSource = playbackItem.playbackSource(
            mediaIndex: selectedMediaIndex
        ) else {
            throw PlexAPIError.noPlayableMedia
        }

        let serverIdentifier = connectionStore.activeConnection?.serverID
            ?? settingsStore.selectedServerIdentifier?.nilIfBlank
        if let extrasPrefixCount = PlexCinemaPreplayRequestPolicy.extrasPrefixCount(
            for: playbackItem,
            startOption: startOption,
            preference: settingsStore.cinemaPreplayPreference
        ) {
            let queue = try await browserStore.cinemaPlayQueue(
                for: playbackItem,
                extrasPrefixCount: extrasPrefixCount
            )
            let firstItem = try await browserStore.refreshedPlayableDetails(
                for: queue.currentItem
            )
            let sourcePreference = PlexPlaybackQueueSourcePreference(
                ratingKey: playbackItem.ratingKey,
                source: selectedPlaybackSource
            )
            guard let firstSource = sourcePreference.source(for: firstItem)
                ?? firstItem.defaultPlaybackSource else {
                throw PlexAPIError.noPlayableMedia
            }
            let plan = try await browserStore.playbackPlan(
                for: firstItem,
                source: firstSource,
                videoQuality: videoQuality,
                startTimeOverride: 0
            )
            return PlexPlaybackPresentation(
                item: firstItem,
                plan: plan,
                queue: queue,
                videoQuality: videoQuality,
                serverIdentifier: serverIdentifier,
                queueSourcePreference: sourcePreference
            )
        }

        async let plan = browserStore.playbackPlan(
            for: playbackItem,
            source: selectedPlaybackSource,
            videoQuality: videoQuality,
            startTimeOverride: startOption.startTimeOverride
        )
        async let queue = playbackQueue(for: playbackItem)
        return try await PlexPlaybackPresentation(
            item: playbackItem,
            plan: plan,
            queue: queue,
            videoQuality: videoQuality,
            serverIdentifier: serverIdentifier
        )
    }
}

private struct PlexPrimaryExtraButton: View {
    let title: String
    let isPreparing: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isPreparing ? "Preparing \(title)" : title, systemImage: "play.rectangle")
        }
        .disabled(!isEnabled || isPreparing)
        .accessibilityLabel(isPreparing ? "Preparing \(title)" : "Play \(title)")
    }
}

struct PlexPlaybackStartControl: View {
    let title: String
    let hasResumePosition: Bool
    let resumeProgress: Double?
    let isPreparing: Bool
    let isEnabled: Bool
    var width: CGFloat = 216
    let action: (PlexPlaybackStartOption) -> Void

    var body: some View {
        if hasResumePosition {
            Menu {
                Button("Play from Beginning", systemImage: "backward.end.fill") {
                    action(.beginning)
                }
            } label: {
                label("Resume")
            } primaryAction: {
                action(.resume)
            }
            .menuStyle(.button)
            .plexCinematicPrimaryButton()
            .disabled(isPreparing || !isEnabled)
            .accessibilityLabel(isPreparing ? "Preparing \(title)" : "Resume \(title)")
            .accessibilityValue(resumeAccessibilityValue)
            .accessibilityHint("Open the menu to play from the beginning.")
        } else {
            Button {
                action(.beginning)
            } label: {
                label("Play")
            }
            .plexCinematicPrimaryButton()
            .accessibilityLabel(isPreparing ? "Preparing \(title)" : "Play \(title)")
            .disabled(isPreparing || !isEnabled)
        }
    }

    @ViewBuilder
    private func label(_ text: String) -> some View {
        ZStack {
            GeometryReader { geometry in
                Rectangle()
                    .fill(.white.opacity(0.88))
                    .frame(width: geometry.size.width * visibleResumeProgress)
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)

            if isPreparing {
                ProgressView()
                    .controlSize(.small)
                    .tint(.black.opacity(0.82))
            } else {
                Label(text, systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .foregroundStyle(.black.opacity(0.90))
            }
        }
        .frame(width: width, height: 44)
        .compositingGroup()
        .clipShape(.capsule)
    }

    private var visibleResumeProgress: Double {
        guard hasResumePosition,
              let resumeProgress,
              resumeProgress.isFinite else {
            return 0
        }
        return min(max(resumeProgress, 0), 1)
    }

    private var resumeAccessibilityValue: String {
        guard visibleResumeProgress > 0 else {
            return ""
        }
        return "\(visibleResumeProgress.formatted(.percent.precision(.fractionLength(0)))) watched"
    }
}
