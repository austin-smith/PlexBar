import Foundation
import Testing
@testable import PlexBar

@Suite
struct PlexMediaSelectionTests {
    @Test func derivesNativeMenuOptionsFromTheSelectedPlexPart() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Movie",
          "Media": [{
            "Part": [{
              "id": "700",
              "Stream": [
                {"id":"21","streamType":"2","displayTitle":"English (AC3 5.1)","languageCode":"eng","selected":"1","codec":"ac3","channels":"6"},
                {"id":"22","streamType":"2","language":"French","languageCode":"fra","codec":"aac","channels":"2","visualImpaired":"1"},
                {"id":"31","streamType":"3","displayTitle":"English","languageCode":"eng","selected":"1","hearingImpaired":"1"},
                {"id":"32","streamType":"3","language":"Spanish","languageCode":"es-419","forced":"1"}
              ]
            }]
          }]
        }
        """#)

        let selection = PlexPlaybackMediaSelection(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
        )

        #expect(selection.partID == 700)
        #expect(selection.audioOptions.map(\.id) == [21, 22])
        #expect(selection.audioOptions[0].isSelected)
        #expect(selection.audioOptions.map(\.languageTag) == ["eng", "fra"])
        #expect(selection.audioOptions[0].title.contains("English (AC3 5.1)"))
        #expect(selection.audioOptions[0].title.contains("6 ch"))
        #expect(selection.audioOptions[1].isVisualImpaired)
        #expect(selection.subtitleOptions.map(\.id) == [31, 32])
        #expect(selection.subtitleOptions.map(\.languageTag) == ["eng", "es-419"])
        #expect(selection.subtitleOptions[0].isSelected)
        #expect(selection.subtitleOptions[0].isHearingImpaired)
        #expect(selection.subtitleOptions[1].isForced)
        #expect(selection.subtitleOptions[0].title.contains("SDH"))
        #expect(selection.subtitleOptions[1].title.contains("Forced"))
        #expect(selection.hasActionMenuItems)
        #expect(selection.canSelectAudioStream(22))
        #expect(!selection.canSelectAudioStream(21))
        #expect(!selection.canSelectAudioStream(999))
        #expect(selection.canSelectSubtitleStream(32))
        #expect(selection.canSelectSubtitleStream(nil))
        #expect(!selection.canSelectSubtitleStream(31))
        #expect(!selection.canSelectSubtitleStream(999))
    }

    @Test func languageMetadataDoesNotGuessMissingOrMalformedBCP47Tags() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Movie",
          "Media": [{
            "Part": [{
              "id": "700",
              "Stream": [
                {"id":"21","streamType":"2","language":"English"},
                {"id":"22","streamType":"2","languageCode":"English US"},
                {"id":"31","streamType":"3","languageCode":"en-US"}
              ]
            }]
          }]
        }
        """#)

        let selection = PlexPlaybackMediaSelection(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
        )

        #expect(selection.audioOptions.map(\.languageTag) == [nil, nil])
        #expect(selection.subtitleOptions.map(\.languageTag) == ["en-US"])
        #expect(!selection.canSelectSubtitleStream(nil))
    }

    @Test func nativeAvailabilityRejectsAnOutgoingPlayerItemGeneration() {
        var state = PlexNativeMediaSelectionState()
        let firstGeneration = state.generation
        let firstAvailability = PlexNativeMediaSelectionAvailability(
            hasAudio: true,
            hasSubtitles: false
        )

        let acceptedFirst = state.accept(firstAvailability, generation: firstGeneration)
        #expect(acceptedFirst)
        #expect(state.availability == firstAvailability)
        let acceptedDuplicate = state.accept(firstAvailability, generation: firstGeneration)
        #expect(!acceptedDuplicate)

        state.beginReload()
        #expect(state.generation == firstGeneration + 1)
        #expect(state.availability == nil)
        let acceptedStale = state.accept(firstAvailability, generation: firstGeneration)
        #expect(!acceptedStale)

        let successorAvailability = PlexNativeMediaSelectionAvailability(
            hasAudio: false,
            hasSubtitles: true
        )
        let acceptedSuccessor = state.accept(
            successorAvailability,
            generation: state.generation
        )
        #expect(acceptedSuccessor)
        #expect(state.availability == successorAvailability)
    }

    @Test func serverManagedMenusWaitForInspectionAndNeverDuplicateAVKitGroups() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Movie",
          "Media": [{
            "Part": [{
              "id": "700",
              "Stream": [
                {"id":"21","streamType":"2","language":"English","selected":"1"},
                {"id":"22","streamType":"2","language":"French"},
                {"id":"31","streamType":"3","language":"English","selected":"1"},
                {"id":"32","streamType":"3","language":"Spanish"}
              ]
            }]
          }]
        }
        """#)
        let selection = PlexPlaybackMediaSelection(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
        )

        let inspectionPending = PlexServerManagedMediaSelection(
            selection: selection,
            nativeAvailability: nil
        )
        #expect(!inspectionPending.hasChoices)

        let allNative = PlexServerManagedMediaSelection(
            selection: selection,
            nativeAvailability: PlexNativeMediaSelectionAvailability(
                hasAudio: true,
                hasSubtitles: true
            )
        )
        #expect(!allNative.hasChoices)

        let subtitlesRequirePlex = PlexServerManagedMediaSelection(
            selection: selection,
            nativeAvailability: PlexNativeMediaSelectionAvailability(
                hasAudio: true,
                hasSubtitles: false
            )
        )
        #expect(subtitlesRequirePlex.audioOptions.isEmpty)
        #expect(subtitlesRequirePlex.subtitleOptions.map(\.id) == [31, 32])
        #expect(subtitlesRequirePlex.canSelectSubtitleStream(nil))
        #expect(subtitlesRequirePlex.canSelectSubtitleStream(32))
        #expect(!subtitlesRequirePlex.canSelectSubtitleStream(31))

        let audioRequiresPlex = PlexServerManagedMediaSelection(
            selection: selection,
            nativeAvailability: PlexNativeMediaSelectionAvailability(
                hasAudio: false,
                hasSubtitles: true
            )
        )
        #expect(audioRequiresPlex.audioOptions.map(\.id) == [21, 22])
        #expect(audioRequiresPlex.subtitleOptions.isEmpty)
        #expect(audioRequiresPlex.canSelectAudioStream(22))
        #expect(!audioRequiresPlex.canSelectAudioStream(21))
    }

    @Test func multipartSelectionUsesTheSelectedPartForServerStreamChanges() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Movie",
          "Media": [{
            "Part": [
              {"id":"700","Stream":[]},
              {"id":"701","selected":"1","Stream":[{"id":"44","streamType":"3","language":"English"}]}
            ]
          }]
        }
        """#)

        let selection = PlexPlaybackMediaSelection(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: -1)
        )

        #expect(selection.partID == 701)
        #expect(selection.subtitleOptions.map(\.id) == [44])
    }

    private func decodeItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }
}
