import PlexClientKit
import PlexModels
import SwiftUI

/// Keep the season picker available when an episode is opened directly from Home.
struct TVSeasonEpisodeBrowser: View {
    @Environment(TVAppStore.self) private var store
    let item: PlexMediaItem
    let selectEpisode: (PlexMediaItem) -> Void

    @State private var seasons: [PlexMediaItem] = []
    @State private var selectedSeasonKey: String?
    @State private var loadedSeasonKey: String?
    @State private var episodes: [PlexMediaItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
                .safeAreaPadding(.horizontal)

            if let seasonKey {
                if loadedSeasonKey != seasonKey {
                    ProgressView("Loading episodes…")
                        .safeAreaPadding(.horizontal)
                } else if episodes.isEmpty {
                    ContentUnavailableView("No Episodes", systemImage: "tv")
                } else {
                    TVMediaShelf(
                        title: "",
                        items: episodes,
                        artworkPreference: .landscape,
                        columnCount: TVLayout.episodeColumns,
                        showsEpisodeNumbers: true,
                        selectedItemID: item.type?.lowercased() == "episode" ? item.id : nil,
                        selectItem: selectEpisode
                    )
                    .accessibilityLabel(seasonTitle)
                }
            }
        }
        .focusSection()
        .task(id: seriesKey) {
            guard let seriesKey else { return }
            let loaded = await store.seriesSeasons(ratingKey: seriesKey)
            guard !Task.isCancelled else { return }
            seasons = loaded
        }
        .task(id: EpisodeLoadIdentity(seasonKey: seasonKey, revision: store.playbackMetadataRevision)) {
            guard let seasonKey else { return }
            let loaded = await store.seasonEpisodes(ratingKey: seasonKey)
            guard !Task.isCancelled else { return }
            episodes = loaded
            loadedSeasonKey = seasonKey
        }
    }

    @ViewBuilder
    private var header: some View {
        if seasons.count > 1, let seasonKey, seasons.contains(where: { $0.ratingKey == seasonKey }) {
            PlexSeasonPicker(seasons: seasons, selection: Binding(
                get: { seasonKey },
                set: { selectedSeasonKey = $0 }
            ))
        } else {
            Text(seasonTitle)
                .font(TVTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var seasonKey: String? {
        if let selectedSeasonKey { return selectedSeasonKey }
        switch item.type?.lowercased() {
        case "episode": return item.parentRatingKey
        case "season": return item.ratingKey
        default: return seasons.first?.ratingKey
        }
    }

    private var seriesKey: String? {
        switch item.type?.lowercased() {
        case "episode": item.grandparentRatingKey
        case "season": item.parentRatingKey
        default: item.ratingKey
        }
    }

    private var seasonTitle: String {
        if let season = seasons.first(where: { $0.ratingKey == seasonKey }) {
            return season.title
        }
        switch item.type?.lowercased() {
        case "episode": return item.parentTitle ?? "Episodes"
        case "season": return item.title
        default: return "Episodes"
        }
    }

    private struct EpisodeLoadIdentity: Hashable {
        let seasonKey: String?
        let revision: UUID
    }
}
