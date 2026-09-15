import Foundation
import Testing
@testable import PlexBar

struct PlexPlaybackSleepTimerTests {
    @Test func timedPresetUsesAnAbsoluteDeadline() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let timer = PlexPlaybackSleepTimer(
            preset: .thirtyMinutes,
            startingAt: start
        )

        #expect(timer.isActive)
        #expect(!timer.stopsAtEndOfItem)
        #expect(timer.deadline == start.addingTimeInterval(30 * 60))
        #expect(timer.remainingTime(at: start.addingTimeInterval(300)) == 1_500)
        #expect(!timer.hasExpired(at: start.addingTimeInterval(1_799)))
        #expect(timer.hasExpired(at: start.addingTimeInterval(1_800)))
        #expect(timer.remainingTime(at: start.addingTimeInterval(1_900)) == 0)
    }

    @Test func endOfItemHasNoWallClockDeadline() {
        let timer = PlexPlaybackSleepTimer(preset: .endOfItem)

        #expect(timer.isActive)
        #expect(timer.stopsAtEndOfItem)
        #expect(timer.deadline == nil)
        #expect(timer.remainingTime() == nil)
        #expect(!timer.hasExpired())
    }

    @Test func offTimerIsInactive() {
        #expect(!PlexPlaybackSleepTimer.off.isActive)
        #expect(!PlexPlaybackSleepTimer.off.stopsAtEndOfItem)
        #expect(PlexPlaybackSleepTimer.off.deadline == nil)
    }
}
