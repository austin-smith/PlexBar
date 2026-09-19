@testable import PlexClientKit
import Foundation
import Testing
@testable import PlexBar

struct PlexTimelineRequestParametersTests {
    @Test
    func activeTimelineClampsPositionsAndOmitsStoppedOnlyFields() {
        let update = PlexTimelineUpdate(
            ratingKey: "42",
            state: .playing,
            time: -250,
            duration: -1,
            sessionIdentifier: "session-1",
            continuing: true
        )

        let values = values(for: update)

        #expect(values["key"] == "/library/metadata/42")
        #expect(values["ratingKey"] == "42")
        #expect(values["state"] == "playing")
        #expect(values["time"] == "0")
        #expect(values["duration"] == "0")
        #expect(values["continuing"] == nil)
        #expect(values["offline"] == nil)
    }

    @Test
    func stoppedTimelineCarriesQueueContinuityAndOfflineState() {
        let update = PlexTimelineUpdate(
            ratingKey: "episode-9",
            state: .stopped,
            time: 90_000,
            duration: 120_000,
            sessionIdentifier: "session-2",
            playQueueItemID: "queue-7",
            continuing: true,
            offline: true
        )

        let values = values(for: update)

        #expect(values["playQueueItemID"] == "queue-7")
        #expect(values["continuing"] == "1")
        #expect(values["offline"] == "1")
    }

    @Test
    func stoppedTimelineExplicitlyReportsThatPlaybackWillNotContinue() {
        let update = PlexTimelineUpdate(
            ratingKey: "movie-4",
            state: .stopped,
            time: 7_200_000,
            duration: 7_200_000,
            sessionIdentifier: "session-3",
            continuing: false
        )

        #expect(values(for: update)["continuing"] == "0")
    }

    private func values(for update: PlexTimelineUpdate) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: PlexTimelineRequestParameters(update: update)
                .queryItems
                .compactMap { item in item.value.map { (item.name, $0) } }
        )
    }
}
