import AVFoundation
import Foundation
import PlexClientKit
import Synchronization
import Testing
@testable import PlexBar

@MainActor
@Suite(.serialized)
struct PlexInitialResumeTests {
    @Test func autoplayWaitsForTheSavedPositionWithoutPlayingTheBeginning() async throws {
        let fixture = try ResumeFixture()
        defer { fixture.close() }
        let engine = PlexPlaybackEngine()
        engine.player.isMuted = true
        defer { engine.stop() }

        try await engine.load(plan: fixture.plan())
        #expect(engine.position == 6)
        #expect(engine.isPreparingInitialPosition)
        #expect(engine.player.timeControlStatus == .paused)
        var playedBeforeResume = false
        try await waitUntil {
            let time = engine.player.currentTime().seconds
            if engine.player.timeControlStatus == .playing && time < 6 {
                playedBeforeResume = true
            }
            return !engine.isPreparingInitialPosition
        }
        #expect(!playedBeforeResume)
        #expect(engine.position >= 6)
        #expect(engine.player.rate == 1)
    }

    @Test func pauseAndRateChangesDuringInitialSeekPreservePausedIntent() async throws {
        let fixture = try ResumeFixture()
        defer { fixture.close() }
        let player = ResumeSeekPlayer()
        let engine = PlexPlaybackEngine(player: player)
        defer { engine.stop() }
        try await engine.load(plan: fixture.plan())
        try await waitUntil { player.pendingSeekCount == 1 }

        engine.pause()
        engine.setPlaybackRate(.oneAndAHalf)
        #expect(player.rate == 0)
        #expect(engine.position == 6)
        player.completeSeek(success: true)
        try await waitUntil { !engine.isPreparingInitialPosition }
        #expect(engine.status == .paused)
        #expect(player.rate == 0)
        #expect(player.defaultRate == 1.5)
    }

    @Test func playAndRateChangesCannotBypassAnInitialSeek() async throws {
        let fixture = try ResumeFixture()
        defer { fixture.close() }
        let player = ResumeSeekPlayer()
        let engine = PlexPlaybackEngine(player: player)
        defer { engine.stop() }
        try await engine.load(plan: fixture.plan(), autoplay: false)
        try await waitUntil { player.pendingSeekCount == 1 }
        engine.play()
        engine.setPlaybackRate(.oneAndAHalf)
        #expect(player.timeControlStatus == .paused)
        #expect(engine.position == 6)
        player.completeSeek(success: true)
        try await waitUntil { !engine.isPreparingInitialPosition }
        #expect(player.rate == 1.5)
    }

    @Test func failedInitialSeekSurfacesFailureAndRetainsRecoveryPosition() async throws {
        let fixture = try ResumeFixture()
        defer { fixture.close() }
        let player = ResumeSeekPlayer()
        let engine = PlexPlaybackEngine(player: player)
        defer { engine.stop() }
        let plan = fixture.plan()
        try await engine.load(plan: plan)
        try await waitUntil { player.pendingSeekCount == 1 }
        player.completeSeek(success: false)
        try await waitUntil { if case .failed = engine.status { true } else { false } }
        engine.play()
        engine.setPlaybackRate(.double)
        try await Task.sleep(for: .milliseconds(300))
        #expect(engine.status == .failed("macOS could not resume this stream at the saved position."))
        #expect(player.rate == 0)
        #expect(engine.position == 6)
        #expect(PlexPlaybackRecoveryRequest(plan: plan, videoQuality: .original, position: engine.position).startTime == 6)
        #expect(player.pendingSeekCount == 0)
    }

    @Test func replacingTheItemRejectsTheOldSeekCompletion() async throws {
        let fixture = try ResumeFixture()
        defer { fixture.close() }
        let player = ResumeSeekPlayer()
        let engine = PlexPlaybackEngine(player: player)
        defer { engine.stop() }
        try await engine.load(plan: fixture.plan())
        try await waitUntil { player.pendingSeekCount == 1 }
        try await engine.load(plan: fixture.plan(startTime: 0), autoplay: false)
        player.completeSeek(success: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(engine.position == 0)
        #expect(player.rate == 0)
        #expect(engine.status == .paused)
    }

    @Test func newerSeekOwnsThePendingPositionAndAutoplay() async throws {
        let fixture = try ResumeFixture()
        defer { fixture.close() }
        let player = ResumeSeekPlayer()
        let engine = PlexPlaybackEngine(player: player)
        defer { engine.stop() }
        try await engine.load(plan: fixture.plan())
        try await waitUntil { player.pendingSeekCount == 1 }
        let request = engine.reserveSeek(to: 8)
        let replacement = Task { await engine.performSeek(request) }
        try await waitUntil { player.pendingSeekCount == 2 }
        player.completeSeek(success: false)
        #expect(engine.position == 8)
        #expect(player.rate == 0)
        player.completeSeek(success: true)
        #expect(await replacement.value)
        #expect(engine.position == 8)
        #expect(!engine.isPreparingInitialPosition)
        #expect(player.rate == 1)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), .now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition(), "Timed out waiting for native player state")
        try #require(condition())
    }
}

private struct ResumeFixture {
    let directory: URL
    let url: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "resume.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100 * 12)!
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].update(repeating: 0, count: Int(buffer.frameLength))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    func plan(startTime: TimeInterval = 6) -> PlexPlaybackPlan {
        PlexPlaybackPlan(url: url, method: .directPlay, mediaKind: .music,
                         sessionIdentifier: UUID().uuidString, ratingKey: "resume-fixture",
                         duration: 12, startTime: startTime,
                         source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0), usesServerMediaSelection: false)
    }

    func close() { try? FileManager.default.removeItem(at: directory) }
}

// AVPlayer's completion callbacks may cross executors. Only the callback queue
// is test-controlled; its storage is locked, and native readiness remains real.
private final class ResumeSeekPlayer: AVPlayer, @unchecked Sendable {
    private let completions = Mutex<[@Sendable (Bool) -> Void]>([])
    var pendingSeekCount: Int { completions.withLock { $0.count } }

    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
                       completionHandler: @escaping @Sendable (Bool) -> Void) {
        completions.withLock { $0.append(completionHandler) }
    }

    func completeSeek(success: Bool) {
        let callback = completions.withLock { $0.removeFirst() }
        callback(success)
    }
}
