import Foundation
import Testing
@testable import PlexBar

@Suite("Plex Autoplay Preferences")
struct PlexAutoplayPreferencesTests {
    private let referenceDate = Date(timeIntervalSince1970: 10_000)

    @Test func eligibleVideoUsesTheConfiguredCountdown() throws {
        let item = try mediaItem(type: "episode", duration: 30 * 60 * 1_000)

        #expect(resolve(
            item: item,
            preferences: preferences(countdown: .fifteenSeconds),
            lastInteractionDate: referenceDate.addingTimeInterval(-60)
        ) == .presentPostPlay(autoAdvanceAfterSeconds: 15))
    }

    @Test func disablingAutoplayKeepsTheNextVideoWaitingForAnExplicitAction() throws {
        let item = try mediaItem(type: "episode", duration: 30 * 60 * 1_000)

        #expect(resolve(
            item: item,
            preferences: preferences(isEnabled: false),
            lastInteractionDate: referenceDate
        ) == .presentPostPlay(autoAdvanceAfterSeconds: nil))
    }

    @Test func passoutProtectionRequiresBothProlongedInactivityAndALongVideo() throws {
        let longEpisode = try mediaItem(type: "episode", duration: 21 * 60 * 1_000)
        let shortEpisode = try mediaItem(type: "episode", duration: 19 * 60 * 1_000)
        let preferences = preferences(passoutProtection: .twoHours)
        let moreThanTwoHoursAgo = referenceDate.addingTimeInterval(-(2 * 60 * 60 + 1))
        let exactlyTwoHoursAgo = referenceDate.addingTimeInterval(-(2 * 60 * 60))

        #expect(resolve(
            item: longEpisode,
            preferences: preferences,
            lastInteractionDate: moreThanTwoHoursAgo
        ) == .presentPostPlay(autoAdvanceAfterSeconds: nil))
        #expect(resolve(
            item: longEpisode,
            preferences: preferences,
            lastInteractionDate: exactlyTwoHoursAgo
        ) == .presentPostPlay(autoAdvanceAfterSeconds: 10))
        #expect(resolve(
            item: shortEpisode,
            preferences: preferences,
            lastInteractionDate: moreThanTwoHoursAgo
        ) == .presentPostPlay(autoAdvanceAfterSeconds: 10))
    }

    @Test func documentedPostPlayExclusionsRemainContinuous() throws {
        let shortVideo = try mediaItem(type: "episode", duration: 5 * 60 * 1_000)
        let trailer = try mediaItem(
            type: "clip",
            subtype: "trailer",
            duration: 12 * 60 * 1_000
        )
        let playlistVideo = try mediaItem(
            type: "movie",
            duration: 90 * 60 * 1_000,
            playlistItemID: "901"
        )
        let preferences = preferences()

        #expect(resolve(item: shortVideo, preferences: preferences) == .advanceNext)
        #expect(resolve(item: trailer, preferences: preferences) == .advanceNext)
        #expect(resolve(item: playlistVideo, preferences: preferences) == .advanceNext)
        #expect(resolve(
            item: try mediaItem(type: "track", duration: 4 * 60 * 1_000),
            mediaKind: .music,
            preferences: preferences
        ) == .advanceNext)
    }

    @Test func immediateCountdownAndExplicitRepeatKeepNativeQueueSemantics() throws {
        let item = try mediaItem(type: "episode", duration: 30 * 60 * 1_000)

        #expect(resolve(
            item: item,
            preferences: preferences(countdown: .immediate)
        ) == .advanceNext)
        #expect(resolve(
            repeatMode: .one,
            item: item,
            preferences: preferences()
        ) == .replayCurrent)
        #expect(PlexPlaybackCompletionAction.resolve(
            repeatMode: .all,
            canAdvance: false,
            canResetQueue: true,
            completedItem: item,
            mediaKind: .video,
            duration: 30 * 60,
            autoplayPreferences: preferences(),
            lastInteractionDate: referenceDate,
            now: referenceDate
        ) == .resetQueue)
    }

    @Test func cinemaPreplayAdvancesDirectlyEvenForALongNonTrailerClip() throws {
        let preRoll = try mediaItem(type: "clip", duration: 12 * 60 * 1_000)

        #expect(resolve(
            item: preRoll,
            preferences: preferences(isEnabled: false),
            isCinemaPreplayItem: true
        ) == .advanceNext)
        #expect(resolve(
            repeatMode: .one,
            item: preRoll,
            preferences: preferences(),
            isCinemaPreplayItem: true
        ) == .replayCurrent)
    }

    private func resolve(
        repeatMode: PlexPlaybackRepeatMode = .off,
        item: PlexMediaItem,
        mediaKind: PlexPlaybackMediaKind = .video,
        preferences: PlexAutoplayPreferences,
        lastInteractionDate: Date? = nil,
        isCinemaPreplayItem: Bool = false
    ) -> PlexPlaybackCompletionAction {
        PlexPlaybackCompletionAction.resolve(
            repeatMode: repeatMode,
            canAdvance: true,
            canResetQueue: true,
            completedItem: item,
            mediaKind: mediaKind,
            duration: item.duration.map { TimeInterval($0) / 1_000 },
            autoplayPreferences: preferences,
            lastInteractionDate: lastInteractionDate ?? referenceDate,
            isCinemaPreplayItem: isCinemaPreplayItem,
            now: referenceDate
        )
    }

    private func preferences(
        isEnabled: Bool = true,
        countdown: PlexAutoplayCountdown = .tenSeconds,
        passoutProtection: PlexPassoutProtection = .twoHours
    ) -> PlexAutoplayPreferences {
        PlexAutoplayPreferences(
            isEnabled: isEnabled,
            countdown: countdown,
            passoutProtection: passoutProtection
        )
    }

    private func mediaItem(
        type: String,
        subtype: String? = nil,
        duration: Int,
        playlistItemID: String? = nil
    ) throws -> PlexMediaItem {
        var fields: [String: Any] = [
            "ratingKey": "42",
            "key": "/library/metadata/42",
            "type": type,
            "title": "Test Item",
            "duration": duration,
            "Media": [],
        ]
        fields["subtype"] = subtype
        fields["playlistItemID"] = playlistItemID
        return try JSONDecoder().decode(
            PlexMediaItem.self,
            from: JSONSerialization.data(withJSONObject: fields)
        )
    }
}
