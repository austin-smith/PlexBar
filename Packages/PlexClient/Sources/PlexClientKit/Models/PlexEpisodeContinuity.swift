import PlexModels
import Foundation

public enum PlexEpisodeContinuity {
    public static func nextEpisode(
        after current: PlexMediaItem,
        in episodes: [PlexMediaItem]
    ) -> PlexMediaItem? {
        nextItem(
            afterRatingKey: current.ratingKey,
            index: current.index,
            in: episodes.filter { $0.type?.lowercased() == "episode" }
        )
    }

    public static func nextSeason(
        afterRatingKey ratingKey: String,
        index: Int?,
        in seasons: [PlexMediaItem]
    ) -> PlexMediaItem? {
        nextItem(
            afterRatingKey: ratingKey,
            index: index,
            in: seasons.filter { $0.type?.lowercased() == "season" }
        )
    }

    public static func ordered(_ items: [PlexMediaItem]) -> [PlexMediaItem] {
        items.sorted { lhs, rhs in
            if lhs.index != rhs.index {
                return (lhs.index ?? .max) < (rhs.index ?? .max)
            }
            return lhs.ratingKey.localizedStandardCompare(rhs.ratingKey) == .orderedAscending
        }
    }

    private static func nextItem(
        afterRatingKey ratingKey: String,
        index: Int?,
        in values: [PlexMediaItem]
    ) -> PlexMediaItem? {
        let orderedValues = ordered(values)
        if let currentIndex = orderedValues.firstIndex(where: { $0.ratingKey == ratingKey }),
           orderedValues.indices.contains(currentIndex + 1) {
            return orderedValues[currentIndex + 1]
        }
        guard let index else { return nil }
        return orderedValues.first { ($0.index ?? .max) > index }
    }
}
