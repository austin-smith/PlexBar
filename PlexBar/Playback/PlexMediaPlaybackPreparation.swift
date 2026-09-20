import PlexClientKit
import Foundation
import PlexModels

/// Shared preparation for detail views and search. Installing the result is a separate, explicit action.
@MainActor
struct PlexMediaPlaybackPreparation {
    let browserStore: PlexBrowserStore
    let settingsStore: PlexSettingsStore
    let connectionStore: PlexConnectionStore

    func prepare(
        for playbackItem: PlexMediaItem,
        startOption: PlexPlaybackStartOption,
        videoQuality: PlexVideoQuality,
        mediaIndex: Int? = nil
    ) async throws -> PlexPlaybackPresentation {
        let source = mediaIndex.map { playbackItem.playbackSource(mediaIndex: $0) }
            ?? playbackItem.defaultPlaybackSource
        guard let selectedPlaybackSource = source else {
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
        async let queue: PlexPlaybackQueue? = playbackItem.continuousPlayQueueType == nil
            ? nil : browserStore.continuousPlayQueue(for: playbackItem)
        return try await PlexPlaybackPresentation(
            item: playbackItem,
            plan: plan,
            queue: queue,
            videoQuality: videoQuality,
            serverIdentifier: serverIdentifier
        )
    }
}
