import PlexClientKit
import PlexModels
import SwiftUI

struct TVMediaDetailView: View {
    @Environment(TVAppStore.self) private var store
    let seedItem: PlexMediaItem

    @State private var resolvedItem: PlexMediaItem?
    @State private var selectedEpisode: PlexMediaItem?
    @State private var children: [PlexMediaItem] = []
    @State private var isLoading = false
    @State private var selectedPlaybackVersionID: Int?
    @State private var showsSummary = false
    @State private var detailError: String?
    @State private var castError: String?
    @State private var episodeSeriesCast: [PlexTag] = []
    @State private var detailReloadID = UUID()
    @State private var castReloadID = UUID()
    @FocusState private var isPlaybackFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
                overview

                if let detailError {
                    loadError(title: "Couldn’t Load Details", message: detailError) {
                        detailReloadID = UUID()
                    }
                }

                if ["show", "season", "episode"].contains(item.type?.lowercased() ?? "") {
                    TVSeasonEpisodeBrowser(item: item, selectEpisode: selectEpisode)
                } else if !children.isEmpty {
                    TVMediaShelf(
                        title: childrenTitle,
                        items: children,
                        artworkPreference: childrenArtworkPreference,
                        showsEpisodeNumbers: item.type == "episode" || item.type == "season"
                    )
                } else if isLoading, !item.isPlayable {
                    ProgressView("Loading \(childrenTitle.lowercased())…")
                        .safeAreaPadding(.horizontal)
                }

                if !people.cast.isEmpty {
                    peopleShelf(title: "Cast", credits: people.cast)
                }

                if !people.crew.isEmpty {
                    peopleShelf(title: "Crew", credits: people.crew)
                }

                if let castError {
                    loadError(title: "Couldn’t Load Cast", message: castError) {
                        castReloadID = UUID()
                    }
                }

                PlexMediaMetadataView(item: item)
                    .frame(maxWidth: 980, alignment: .leading)
                    .safeAreaPadding(.horizontal)

                TVDetailDiscoveryView(item: item)
                    .id(item.id)
            }
            .safeAreaPadding(.bottom)
            .background(alignment: .top) {
                TVArtworkImage(path: item.preferredBackdropPath, width: 1920, height: 1080) { image in
                    PlexCinematicBackdrop(
                        image: image,
                        pageBackground: TVTheme.canvas,
                        contentPlacement: .leading
                    )
                }
                .containerRelativeFrame(.vertical)
                .ignoresSafeArea(edges: .horizontal)
            }
        }
        .scrollClipDisabled()
        .defaultFocus($isPlaybackFocused, true, priority: .userInitiated)
        .ignoresSafeArea(.container, edges: .top)
        .background(TVCanvasBackground())
        .toolbarVisibility(.hidden, for: .tabBar)
        .sheet(isPresented: $showsSummary) {
            VStack(alignment: .leading, spacing: 28) {
                Text(item.title)
                    .font(TVTypography.sectionTitle)
                    .lineLimit(2)
                ScrollView {
                    Text(item.summary ?? "")
                        .font(TVTypography.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusable()
                }
                .frame(height: 280)
                Button("Done") { showsSummary = false }
            }
            .padding(60)
            .frame(width: 1100)
            .presentationSizing(.fitted)
        }
        .task(id: DetailsIdentity(itemID: selectedEpisode?.id ?? seedItem.id, playbackRevision: store.playbackMetadataRevision, reloadID: detailReloadID)) {
            await loadDetails()
        }
        .task(id: DetailsIdentity(itemID: item.episodeSeriesCastRatingKey ?? "", playbackRevision: store.playbackMetadataRevision, reloadID: castReloadID)) {
            await loadSeriesCast()
        }
        .navigationDestination(for: TVNavigationRoute.self) { route in
            TVNavigationDestination(route: route)
        }
    }

    private var item: PlexMediaItem {
        resolvedItem ?? selectedEpisode ?? seedItem
    }

    private struct DetailsIdentity: Hashable {
        let itemID: String
        let playbackRevision: UUID
        let reloadID: UUID
    }

    private var people: PlexCastAndCrewPresentation {
        PlexCastAndCrewPresentation(item: item, episodeSeriesCast: episodeSeriesCast)
    }

    private var overview: some View {
        TVCinematicMediaHero(item: item, showSummary: { showsSummary = true }) {
            actionButtons
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                if item.tvCanStartPlayback {
                    TVPlaybackButton(item: item, title: item.tvResumeTitle, fillsAvailableWidth: false,
                                     isIconOnly: item.resumeSeconds <= 0, action: play)
                        .accessibilityIdentifier("detail-play.\(item.ratingKey)")
                        .focused($isPlaybackFocused)
                }

                if let primaryExtraTitle = item.primaryExtraActionTitle {
                    TVPlaybackButton(
                        item: item,
                        title: primaryExtraTitle,
                        systemImage: "play.rectangle.fill",
                        preparationKind: .primaryExtra,
                        fillsAvailableWidth: false,
                        isIconOnly: true,
                        action: playPrimaryExtra
                    )
                }

                if item.isPlayable, item.resumeSeconds > 0 {
                    Button("Play from Beginning", systemImage: "arrow.counterclockwise", action: playFromBeginning)
                        .labelStyle(.iconOnly)
                        .font(TVTypography.action)
                        .accessibilityLabel("Play from Beginning")
                }

                if playbackVersionOptions.count > 1 {
                    Menu {
                        Picker("Version", selection: playbackVersionBinding) {
                            ForEach(playbackVersionOptions) { option in
                                Text(option.label).tag(option.id)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Version", systemImage: "square.stack")
                            .labelStyle(.iconOnly)
                            .font(TVTypography.action)
                    }
                    .accessibilityLabel("Version")
                    .accessibilityValue(selectedPlaybackVersion?.label ?? "")
                    .accessibilityIdentifier("detail-version-picker")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .controlSize(.regular)
    }

    private func peopleShelf(
        title: String,
        credits: [PlexCastAndCrewCredit]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(TVTypography.sectionTitle)
                .safeAreaPadding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: TVLayout.cardSpacing) {
                    ForEach(credits) { credit in
                        TVPersonLockup(credit: credit)
                    }
                }
                .safeAreaPadding(.horizontal)
            }
            .scrollClipDisabled()
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .focusSection()
    }

    private var childrenTitle: String {
        switch item.type?.lowercased() {
        case "show": "Seasons"
        case "season": "Episodes"
        case "episode": item.parentTitle ?? "Episodes"
        case "artist": "Albums"
        case "album": "Tracks"
        default: "More"
        }
    }

    private var childrenArtworkPreference: TVMediaShelf.ArtworkPreference {
        switch item.type?.lowercased() {
        case "show": .automatic
        case "season", "episode": .landscape
        default: .automatic
        }
    }

    private var playbackVersionOptions: [PlexPlaybackVersionOption] {
        item.playbackVersionOptions
    }

    private var selectedPlaybackVersion: PlexPlaybackVersionOption? {
        let selectedID = selectedPlaybackVersionID
            ?? item.defaultPlaybackSource?.mediaIndex
        return playbackVersionOptions.first { $0.id == selectedID }
    }

    private var playbackVersionBinding: Binding<Int> {
        Binding(
            get: {
                selectedPlaybackVersion?.id
                    ?? playbackVersionOptions.first?.id
                    ?? 0
            },
            set: { selectedPlaybackVersionID = $0 }
        )
    }

    private func loadDetails() async {
        isLoading = true
        detailError = nil
        do {
            let value = try await store.resolvedItem(selectedEpisode ?? seedItem)
            guard !Task.isCancelled else { return }
            resolvedItem = value
            if !value.playbackVersionOptions.contains(where: {
                $0.id == selectedPlaybackVersionID
            }) {
                selectedPlaybackVersionID = value.defaultPlaybackSource?.mediaIndex
            }
            if !value.isPlayable, !["show", "season"].contains(value.type?.lowercased() ?? "") {
                let loadedChildren = try await store.children(of: value)
                guard !Task.isCancelled else { return }
                children = loadedChildren
            }
        } catch {
            guard !Task.isCancelled else { return }
            detailError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadSeriesCast() async {
        episodeSeriesCast = []
        castError = nil
        guard item.episodeSeriesCastRatingKey != nil else { return }
        do {
            let cast = try await store.episodeSeriesCast(for: item)
            guard !Task.isCancelled else { return }
            episodeSeriesCast = cast
        } catch {
            guard !Task.isCancelled else { return }
            castError = error.localizedDescription
        }
    }

    private func loadError(title: String, message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(TVTypography.sectionTitle)
            Text(message)
                .font(TVTypography.metadata)
                .foregroundStyle(.secondary)
            Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                .font(TVTypography.action)
        }
        .safeAreaPadding(.horizontal)
    }

    private func play() {
        store.play(item, source: selectedPlaybackVersion?.source)
    }

    private func selectEpisode(_ episode: PlexMediaItem) {
        guard episode.ratingKey != item.ratingKey else { return }
        selectedEpisode = episode
        resolvedItem = nil
        selectedPlaybackVersionID = nil
    }

    private func playFromBeginning() {
        store.play(
            item,
            source: selectedPlaybackVersion?.source,
            resume: false
        )
    }

    private func playPrimaryExtra() {
        store.playPrimaryExtra(for: item)
    }
}
