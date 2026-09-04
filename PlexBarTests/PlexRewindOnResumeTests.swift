import Foundation
import Testing
@testable import PlexBar

@Suite
struct PlexRewindOnResumeTests {
    @Test func settingCoversNoneThroughThirtySecondsAndFormatsNativeValues() {
        #expect(PlexRewindOnResume(seconds: -1) == .none)
        #expect(PlexRewindOnResume(seconds: 0).label == "None")
        #expect(PlexRewindOnResume(seconds: 1).label == "1 Second")
        #expect(PlexRewindOnResume(seconds: 12).label == "12 Seconds")
        #expect(PlexRewindOnResume(seconds: 31).seconds == 30)
    }

    @Test func targetRewindsAndClampsAtTheBeginning() {
        let preference = PlexRewindOnResume(seconds: 10)

        #expect(preference.target(from: 42) == 32)
        #expect(preference.target(from: 4) == 0)
        #expect(preference.target(from: 0) == nil)
        #expect(preference.target(from: .nan) == nil)
        #expect(PlexRewindOnResume.none.target(from: 42) == nil)
    }

    @Test func policyAppliesOnlyToAnInSessionPausedResume() {
        let preference = PlexRewindOnResume(seconds: 10)

        #expect(PlexRewindOnResumePolicy.action(
            status: .paused,
            position: 42,
            preference: preference
        ) == .seekThenPlay(target: 32))
        #expect(PlexRewindOnResumePolicy.action(
            status: .paused,
            position: 42,
            preference: .none
        ) == .playImmediately)

        for status in [
            PlexPlaybackStatus.idle,
            .preparing,
            .playing,
            .buffering,
            .ended,
            .failed("Unavailable"),
        ] {
            #expect(PlexRewindOnResumePolicy.action(
                status: status,
                position: 42,
                preference: preference
            ) == nil)
        }
    }

    @Test func pendingRewindRemainsPauseableUntilItsSeekCompletes() {
        #expect(PlexRewindOnResumePolicy.transportAction(
            status: .paused,
            hasPendingRewind: true
        ) == .pause)
        #expect(PlexRewindOnResumePolicy.transportAction(
            status: .paused,
            hasPendingRewind: false
        ) == .play)
    }
}
