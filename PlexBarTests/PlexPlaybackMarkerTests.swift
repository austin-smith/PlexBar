import PlexModels
import Foundation
import Testing
@testable import PlexBar

struct PlexPlaybackMarkerTests {
    @Test func metadataDecodesPlexMarkerTimingAndFinalFlag() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Episode",
          "type": "episode",
          "Marker": [
            {
              "id": 101,
              "type": "intro",
              "startTimeOffset": "30000",
              "endTimeOffset": 92000
            },
            {
              "id": "102",
              "type": "credits",
              "startTimeOffset": 2500000,
              "endTimeOffset": 2580000,
              "final": "1"
            }
          ]
        }
        """#)

        #expect(item.markers.count == 2)
        #expect(item.markers[0].id == "101")
        #expect(item.markers[0].startTimeOffset == 30_000)
        #expect(item.markers[0].endTimeOffset == 92_000)
        #expect(item.markers[1].id == "102")
        #expect(item.markers[1].isFinal == true)
    }

    @Test func skipActionIsAvailableOnlyInsideRecognizedMarkerBounds() throws {
        let markers = try decodeMarkers(#"""
        [
          { "id": 1, "type": "commercial", "startTimeOffset": 0, "endTimeOffset": 10000 },
          { "id": 2, "type": "intro", "startTimeOffset": 30000, "endTimeOffset": 92000 },
          { "id": 3, "type": "credit", "startTimeOffset": 2500000, "endTimeOffset": 2580000 }
        ]
        """#)

        let commercial = try #require(
            PlexPlaybackMarkerAction.active(in: markers, at: 0, duration: 2_600)
        )
        #expect(commercial.id == "1")
        #expect(commercial.kind == .commercial)
        #expect(commercial.label == "Skip Ads")
        #expect(commercial.accessibilityHint == "Moves playback to the end of the commercial break.")
        #expect(commercial.targetTime == 10)
        #expect(PlexPlaybackMarkerAction.active(in: markers, at: 10, duration: 2_600) == nil)

        #expect(PlexPlaybackMarkerAction.active(in: markers, at: 29.999, duration: 2_600) == nil)

        let intro = try #require(
            PlexPlaybackMarkerAction.active(in: markers, at: 30, duration: 2_600)
        )
        #expect(intro.id == "2")
        #expect(intro.kind == .intro)
        #expect(intro.label == "Skip Intro")
        #expect(intro.targetTime == 92)
        #expect(PlexPlaybackMarkerAction.active(in: markers, at: 92, duration: 2_600) == nil)

        let credits = try #require(
            PlexPlaybackMarkerAction.active(in: markers, at: 2_500, duration: 2_600)
        )
        #expect(credits.kind == .credits)
        #expect(credits.label == "Skip Credits")
        #expect(credits.targetTime == 2_580)
    }

    @Test func skipActionClampsToDurationAndRejectsInvalidMarkers() throws {
        let markers = try decodeMarkers(#"""
        [
          { "type": "intro", "startTimeOffset": 10000 },
          { "type": "credits", "startTimeOffset": 90000, "endTimeOffset": 110000 }
        ]
        """#)

        let credits = try #require(
            PlexPlaybackMarkerAction.active(in: markers, at: 95, duration: 100)
        )
        #expect(credits.id == "credits:90000:110000")
        #expect(credits.targetTime == 100)
        #expect(PlexPlaybackMarkerAction.active(in: markers, at: 100, duration: 100) == nil)
    }

    @Test func overlappingRecognizedMarkersChooseTheEarliestServerRange() throws {
        let markers = try decodeMarkers(#"""
        [
          { "id": 9, "type": "credits", "startTimeOffset": 40000, "endTimeOffset": 90000 },
          { "id": 8, "type": "intro", "startTimeOffset": 30000, "endTimeOffset": 80000 }
        ]
        """#)

        let action = try #require(
            PlexPlaybackMarkerAction.active(in: markers, at: 50, duration: 120)
        )
        #expect(action.id == "8")
        #expect(action.kind == .intro)
    }

    @Test func publishedCreditSchemaAndCreditsExampleMapToTheSameAction() throws {
        let markers = try decodeMarkers(#"""
        [
          { "id": 1, "type": "credit", "startTimeOffset": 10000, "endTimeOffset": 20000 },
          { "id": 2, "type": "credits", "startTimeOffset": 30000, "endTimeOffset": 40000 }
        ]
        """#)

        #expect(
            PlexPlaybackMarkerAction.active(in: markers, at: 15, duration: 60)?.kind == .credits
        )
        #expect(
            PlexPlaybackMarkerAction.active(in: markers, at: 35, duration: 60)?.kind == .credits
        )
    }

    @Test func creditsStartUsesTheEarliestValidServerRange() throws {
        let markers = try decodeMarkers(#"""
        [
          { "id": 1, "type": "intro", "startTimeOffset": 10000, "endTimeOffset": 20000 },
          { "id": 2, "type": "credits", "startTimeOffset": 90000, "endTimeOffset": 110000 },
          { "id": 3, "type": "credit", "startTimeOffset": 70000, "endTimeOffset": 80000 },
          { "id": 4, "type": "credits", "startTimeOffset": 60000, "endTimeOffset": 60000 },
          { "id": 5, "type": "credits", "startTimeOffset": 130000, "endTimeOffset": 140000 }
        ]
        """#)

        #expect(PlexPlaybackMarkerAction.creditsStartTime(in: markers, duration: 120) == 70)
        #expect(PlexPlaybackMarkerAction.creditsStartTime(in: markers, duration: 65) == nil)
    }

    @Test func manualPresentationFollowsTheExactPerMarkerPreference() throws {
        let markers = try decodeMarkers(#"""
        [
          { "id": 1, "type": "intro", "startTimeOffset": 10000, "endTimeOffset": 20000 },
          { "id": 2, "type": "commercial", "startTimeOffset": 30000, "endTimeOffset": 40000 },
          { "id": 3, "type": "credits", "startTimeOffset": 50000, "endTimeOffset": 60000 }
        ]
        """#)
        let preferences = PlexPlaybackMarkerPreferences(
            intro: .manually,
            ads: .disabled,
            credits: .automatically
        )

        #expect(
            PlexPlaybackMarkerAction.manual(
                in: markers,
                at: 15,
                duration: 70,
                preferences: preferences
            )?.kind == .intro
        )
        #expect(
            PlexPlaybackMarkerAction.manual(
                in: markers,
                at: 35,
                duration: 70,
                preferences: preferences
            ) == nil
        )
        #expect(
            PlexPlaybackMarkerAction.manual(
                in: markers,
                at: 55,
                duration: 70,
                preferences: preferences
            ) == nil
        )
    }

    @Test func automaticTransitionRunsOncePerMarkerEntryAndRearmsAfterLeaving() throws {
        let markers = try decodeMarkers(#"""
        [{ "id": 1, "type": "intro", "startTimeOffset": 10000, "endTimeOffset": 20000 }]
        """#)
        let action = try #require(
            PlexPlaybackMarkerAction.active(in: markers, at: 15, duration: 30)
        )
        let preferences = PlexPlaybackMarkerPreferences(
            intro: .automatically,
            ads: .manually,
            credits: .manually
        )
        var transition = PlexAutomaticPlaybackMarkerTransition()

        #expect(transition.action(for: action, preferences: preferences) == action)
        #expect(transition.action(for: action, preferences: preferences) == nil)
        #expect(transition.action(for: nil, preferences: preferences) == nil)
        #expect(transition.action(for: action, preferences: preferences) == action)

        transition.retry(action)
        #expect(transition.action(for: action, preferences: preferences) == action)

        transition.reset()
        #expect(transition.enteredAction == nil)
    }

    @Test func automaticTransitionNeverConsumesDisabledOrManualMarkers() throws {
        let markers = try decodeMarkers(#"""
        [{ "id": 1, "type": "credits", "startTimeOffset": 10000, "endTimeOffset": 20000 }]
        """#)
        let action = try #require(
            PlexPlaybackMarkerAction.active(in: markers, at: 15, duration: 30)
        )
        var transition = PlexAutomaticPlaybackMarkerTransition()

        for behavior in [PlexPlaybackMarkerBehavior.disabled, .manually] {
            let preferences = PlexPlaybackMarkerPreferences(
                intro: .manually,
                ads: .manually,
                credits: behavior
            )
            #expect(transition.action(for: action, preferences: preferences) == nil)
            #expect(transition.enteredAction == nil)
        }
    }

    @Test func validActionsAndAvailableKindsUseStablePlaybackOrder() throws {
        let markers = try decodeMarkers(#"""
        [
          { "id": 4, "type": "credits", "startTimeOffset": 90000, "endTimeOffset": 110000 },
          { "id": 2, "type": "commercial", "startTimeOffset": 30000, "endTimeOffset": 40000 },
          { "id": 1, "type": "intro", "startTimeOffset": 10000, "endTimeOffset": 20000 },
          { "id": 3, "type": "commercial", "startTimeOffset": 30000, "endTimeOffset": 50000 },
          { "id": 5, "type": "preview", "startTimeOffset": 60000, "endTimeOffset": 70000 },
          { "id": 6, "type": "credits", "startTimeOffset": 120000, "endTimeOffset": 130000 }
        ]
        """#)

        let actions = PlexPlaybackMarkerAction.actions(in: markers, duration: 120)

        #expect(actions.map(\.id) == ["1", "2", "3", "4"])
        #expect(actions.last?.targetTime == 110)
        #expect(PlexPlaybackMarkerAction.availableKinds(in: markers, duration: 120) == [
            .intro,
            .commercial,
            .credits,
        ])
    }

    @Test func commercialInterstitialsUseAllValidPlexAdsAndMergeOverlaps() throws {
        let markers = try decodeMarkers(#"""
        [
          { "id": 1, "type": "commercial", "startTimeOffset": 30000, "endTimeOffset": 45000 },
          { "id": 2, "type": "intro", "startTimeOffset": 10000, "endTimeOffset": 20000 },
          { "id": 3, "type": "commercial", "startTimeOffset": 40000, "endTimeOffset": 60000 },
          { "id": 4, "type": "commercial", "startTimeOffset": 60000, "endTimeOffset": 70000 },
          { "id": 5, "type": "commercial", "startTimeOffset": 90000, "endTimeOffset": 130000 },
          { "id": 6, "type": "commercial", "startTimeOffset": 140000, "endTimeOffset": 150000 }
        ]
        """#)

        #expect(PlexPlaybackInterstitial.commercials(in: markers, duration: 120) == [
            PlexPlaybackInterstitial(startTime: 30, duration: 40),
            PlexPlaybackInterstitial(startTime: 90, duration: 30),
        ])
    }

    private func decodeItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }

    private func decodeMarkers(_ json: String) throws -> [PlexMediaMarker] {
        try JSONDecoder().decode([PlexMediaMarker].self, from: Data(json.utf8))
    }
}
