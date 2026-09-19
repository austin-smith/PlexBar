import PlexModels
import AppKit
import AVFoundation
import AVKit
import Foundation
import SwiftUI
import Testing
@testable import PlexBar

@MainActor
struct PlexPlaybackEngineTests {
    @Test func videoDynamicRangeMapsExactlyToTheMacOS26LayerPolicy() {
        #expect(PlexVideoDisplayDynamicRange.automatic.layerDynamicRange == .automatic)
        #expect(PlexVideoDisplayDynamicRange.standard.layerDynamicRange == .standard)
        #expect(PlexVideoDisplayDynamicRange.constrainedHigh.layerDynamicRange == .constrainedHigh)
        #expect(PlexVideoDisplayDynamicRange.high.layerDynamicRange == .high)
        #expect(PlexVideoDisplayDynamicRange.allCases.map(\.label) == [
            "Automatic",
            "Standard Dynamic Range",
            "Constrained High Dynamic Range",
            "High Dynamic Range",
        ])
    }

    @Test func videoScalingPreservesAspectRatioForFitAndFill() {
        #expect(PlexVideoScalingMode.fit.avVideoGravity == .resizeAspect)
        #expect(PlexVideoScalingMode.fill.avVideoGravity == .resizeAspectFill)
        #expect(PlexVideoScalingMode.allCases.map(\.label) == ["Fit", "Fill"])

        let playerView = AVPlayerView()
        PlexNativeVideoScalingConfiguration.apply(to: playerView, scalingMode: .fill)
        #expect(playerView.videoGravity == .resizeAspectFill)

        PlexNativeVideoScalingConfiguration.apply(to: playerView, scalingMode: .fit)
        #expect(playerView.videoGravity == .resizeAspect)
    }

    @Test func nativeWaitingReasonsMapExactlyAndTransientEvaluationStaysOutOfUI() {
        #expect(waitingReason(.toMinimizeStalls) == .minimizingStalls)
        #expect(waitingReason(.toMinimizeStalls)?.diagnosticLabel == "Minimizing Stalls")
        #expect(waitingReason(.noItemToPlay) == .noItemToPlay)
        #expect(waitingReason(.noItemToPlay)?.diagnosticLabel == "No Item to Play")
        #expect(
            waitingReason(.waitingForCoordinatedPlayback) == .coordinatedPlayback
        )
        #expect(
            waitingReason(.waitingForCoordinatedPlayback)?.diagnosticLabel
                == "Coordinated Playback"
        )
        #expect(waitingReason(.interstitialEvent) == .interstitialEvent)
        #expect(waitingReason(.interstitialEvent)?.diagnosticLabel == "Interstitial Event")

        let evaluating = waitingReason(.evaluatingBufferingRate)
        #expect(evaluating == .evaluatingBufferingRate)
        #expect(evaluating?.diagnosticLabel == nil)

        let futureReason = AVPlayer.WaitingReason(rawValue: "Future AVPlayer waiting reason")
        #expect(waitingReason(futureReason) == nil)
        #expect(waitingReason(nil) == nil)
        #expect(PlexPlaybackWaitingReason(
            timeControlStatus: .playing,
            nativeReason: .toMinimizeStalls
        ) == nil)
        #expect(PlexPlaybackWaitingReason(
            timeControlStatus: .paused,
            nativeReason: .noItemToPlay
        ) == nil)
    }

    @Test func playerNavigationTitleUsesTheCurrentMediaTitleAndAnEmptyFallback() {
        #expect(PlexPlayerNavigationTitle.resolve("Arrival") == "Arrival")
        #expect(PlexPlayerNavigationTitle.resolve("  The Bear\n") == "The Bear")
        #expect(PlexPlayerNavigationTitle.resolve(" \n\t ") == "Player")
        #expect(PlexPlayerNavigationTitle.resolve(nil) == "Player")
    }

    private func waitingReason(
        _ nativeReason: AVPlayer.WaitingReason?
    ) -> PlexPlaybackWaitingReason? {
        PlexPlaybackWaitingReason(
            timeControlStatus: .waitingToPlayAtSpecifiedRate,
            nativeReason: nativeReason
        )
    }

    @Test func endNotificationIsTheAuthoritativeCompletionSignal() async throws {
        let engine = PlexPlaybackEngine()
        let plan = PlexPlaybackPlan(
            url: URL(fileURLWithPath: "/tmp/plexbar-end-notification-test.mp4"),
            method: .directPlay,
            mediaKind: .video,
            sessionIdentifier: "session-1",
            ratingKey: "42",
            duration: 120,
            startTime: 0,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
            usesServerMediaSelection: false
        )

        try await engine.load(plan: plan)
        await Task.yield()
        let item = try #require(engine.player.currentItem)
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )

        for _ in 0..<20 where engine.status != .ended {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(engine.status == .ended)
        #expect(engine.position == 120)
        engine.stop()
    }

    @Test func unexpectedTimeJumpsBelongOnlyToTheExactCurrentItem() async throws {
        let engine = PlexPlaybackEngine()
        let firstPlan = playbackPlan(
            sessionIdentifier: "time-jump-first",
            ratingKey: "first"
        )
        let secondPlan = playbackPlan(
            sessionIdentifier: "time-jump-second",
            ratingKey: "second"
        )

        try await engine.load(plan: firstPlan, autoplay: false)
        await Task.yield()
        let firstItem = try #require(engine.player.currentItem)

        try await engine.load(plan: secondPlan, autoplay: false)
        await Task.yield()
        let secondItem = try #require(engine.player.currentItem)

        NotificationCenter.default.post(
            name: AVPlayerItem.timeJumpedNotification,
            object: firstItem
        )
        try await Task.sleep(for: .milliseconds(20))
        #expect(engine.unexpectedTimeJumpRevision == 0)

        NotificationCenter.default.post(
            name: AVPlayerItem.timeJumpedNotification,
            object: secondItem
        )
        for _ in 0..<20 where engine.unexpectedTimeJumpRevision == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(engine.unexpectedTimeJumpRevision == 1)

        engine.stop()
        NotificationCenter.default.post(
            name: AVPlayerItem.timeJumpedNotification,
            object: secondItem
        )
        try await Task.sleep(for: .milliseconds(20))
        #expect(engine.unexpectedTimeJumpRevision == 1)
    }

    @Test func ownedTimeJumpExpectationsAreBoundedAndConsumedExactlyOnce() {
        var expectations = PlexPlaybackTimeJumpExpectations()
        let first = expectations.expect(target: 42)

        #expect(first != nil)
        #expect(expectations.retainedCount == 1)
        let rejectedDistantPosition = expectations.consume(position: 41.7)
        let consumedExpectedPosition = expectations.consume(position: 42.2)
        let rejectedDuplicatePosition = expectations.consume(position: 42.2)
        #expect(!rejectedDistantPosition)
        #expect(consumedExpectedPosition)
        #expect(!rejectedDuplicatePosition)
        #expect(expectations.retainedCount == 0)

        let cancelled = expectations.expect(target: 80)
        expectations.cancel(cancelled)
        let consumedCancelledPosition = expectations.consume(position: 80)
        #expect(!consumedCancelledPosition)

        let infiniteTarget = expectations.expect(target: -.infinity)
        let negativeTarget = expectations.expect(target: -1)
        #expect(infiniteTarget == nil)
        #expect(negativeTarget == nil)

        for target in 0..<(PlexPlaybackTimeJumpExpectations.maximumRetainedCount + 3) {
            _ = expectations.expect(target: TimeInterval(target))
        }
        #expect(
            expectations.retainedCount
                == PlexPlaybackTimeJumpExpectations.maximumRetainedCount
        )

        expectations.invalidate()
        #expect(expectations.retainedCount == 0)
    }

    @Test func displaySleepPreventionFollowsSelectedMediaKindAcrossLoadsAndStop() async throws {
        let engine = PlexPlaybackEngine()
        let videoPlan = PlexPlaybackPlan(
            url: URL(fileURLWithPath: "/tmp/plexbar-display-sleep-video.mp4"),
            method: .directPlay,
            mediaKind: .video,
            sessionIdentifier: "video-session",
            ratingKey: "video-42",
            duration: 120,
            startTime: 0,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
            usesServerMediaSelection: false
        )
        let musicPlan = PlexPlaybackPlan(
            url: URL(fileURLWithPath: "/tmp/plexbar-display-sleep-music.m4a"),
            method: .directPlay,
            mediaKind: .music,
            sessionIdentifier: "music-session",
            ratingKey: "music-42",
            duration: 180,
            startTime: 0,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
            usesServerMediaSelection: false
        )

        #expect(!engine.player.preventsDisplaySleepDuringVideoPlayback)

        try await engine.load(plan: videoPlan, autoplay: false)
        #expect(engine.player.preventsDisplaySleepDuringVideoPlayback)

        try await engine.load(plan: musicPlan, autoplay: false)
        #expect(!engine.player.preventsDisplaySleepDuringVideoPlayback)

        try await engine.load(plan: videoPlan, autoplay: false)
        #expect(engine.player.preventsDisplaySleepDuringVideoPlayback)

        engine.stop()
        #expect(!engine.player.preventsDisplaySleepDuringVideoPlayback)
    }

    @Test func coordinatorCloseStopsTheNativePlayerSynchronously() async throws {
        let itemData = Data(#"{"ratingKey":"42","title":"Stop Test","type":"movie","Media":[]}"#.utf8)
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: itemData)
        let plan = PlexPlaybackPlan(
            url: URL(fileURLWithPath: "/tmp/plexbar-synchronous-stop-test.mp4"),
            method: .directPlay,
            mediaKind: .video,
            sessionIdentifier: "synchronous-stop-session",
            ratingKey: item.ratingKey,
            duration: 120,
            startTime: 0,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
            usesServerMediaSelection: false
        )
        let presentation = PlexPlaybackPresentation(
            item: item,
            plan: plan,
            queue: nil,
            videoQuality: .original
        )
        let defaultsName = "PlexPlaybackEngineTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let credentials = PlexStoredCredentials(userToken: "", serverToken: "")
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(credentials: credentials),
            initialCredentials: credentials
        )
        let browserStore = PlexBrowserStore(
            connectionStore: PlexConnectionStore(settings: settings),
            playbackCapabilities: PlexPlaybackCapabilities(
                directPlayContainers: [],
                directPlayVideoCodecs: [],
                directPlayAudioCodecs: []
            )
        )
        let coordinator = PlexPlayerCoordinator()
        coordinator.present(presentation)
        let session = coordinator.session(
            for: presentation,
            browserStore: browserStore
        )

        try await session.engine.load(plan: plan, autoplay: false)
        #expect(session.engine.player.currentItem != nil)

        coordinator.close(session)

        #expect(session.engine.player.currentItem == nil)
        #expect(session.engine.status == .idle)
        #expect(!session.engine.player.preventsDisplaySleepDuringVideoPlayback)
    }

    @Test func coordinatorPublishesOnlyItsActiveSessionsExactCurrentItem() throws {
        let firstItem = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(
                #"{"ratingKey":"41","title":"First","type":"movie","Media":[]}"#.utf8
            )
        )
        let secondItem = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(
                #"{"ratingKey":"42","title":"Second","type":"movie","Media":[{"Part":[{"id":"700","Stream":[{"id":"21","streamType":"2","language":"English","selected":"1"},{"id":"22","streamType":"2","language":"French"}]}]}]}"#.utf8
            )
        )
        let refreshedSecondItem = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(
                #"{"ratingKey":"42","title":"Second Updated","type":"movie","Media":[]}"#.utf8
            )
        )
        let firstPresentation = PlexPlaybackPresentation(
            item: firstItem,
            plan: playbackPlan(
                sessionIdentifier: "first-session",
                ratingKey: firstItem.ratingKey
            ),
            queue: nil,
            videoQuality: .original,
            serverIdentifier: " server-a\n"
        )
        let secondPresentation = PlexPlaybackPresentation(
            item: secondItem,
            plan: playbackPlan(
                sessionIdentifier: "second-session",
                ratingKey: secondItem.ratingKey
            ),
            queue: nil,
            videoQuality: .original,
            serverIdentifier: "server-b"
        )
        let refreshedSecondPresentation = PlexPlaybackPresentation(
            item: refreshedSecondItem,
            plan: secondPresentation.plan,
            queue: nil,
            videoQuality: .original,
            serverIdentifier: secondPresentation.serverIdentifier
        )
        let defaultsName = "PlexPlaybackEngineTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let credentials = PlexStoredCredentials(userToken: "", serverToken: "")
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(credentials: credentials),
            initialCredentials: credentials
        )
        let browserStore = PlexBrowserStore(
            connectionStore: PlexConnectionStore(settings: settings),
            playbackCapabilities: PlexPlaybackCapabilities(
                directPlayContainers: [],
                directPlayVideoCodecs: [],
                directPlayAudioCodecs: []
            )
        )
        let coordinator = PlexPlayerCoordinator()

        #expect(coordinator.currentPlayback == nil)
        coordinator.present(firstPresentation)
        let firstSession = coordinator.session(
            for: firstPresentation,
            browserStore: browserStore
        )
        #expect(coordinator.currentPlayback?.item == firstItem)
        #expect(coordinator.currentPlayback?.serverIdentifier == "server-a")
        #expect(coordinator.currentPlayback?.belongs(to: "server-a") == true)
        #expect(coordinator.currentPlayback?.belongs(to: "server-b") == false)

        coordinator.present(secondPresentation)
        let secondSession = coordinator.session(
            for: secondPresentation,
            browserStore: browserStore
        )
        #expect(coordinator.currentPlayback?.item == secondItem)

        coordinator.installTransport(
            for: secondSession,
            status: .paused,
            canToggle: true,
            toggle: {},
            stop: {}
        )
        coordinator.installServerManagedMediaSelection(
            for: secondSession,
            selection: PlexServerManagedMediaSelection(
                selection: PlexPlaybackMediaSelection(
                    item: secondItem,
                    source: secondPresentation.plan.source
                ),
                nativeAvailability: PlexNativeMediaSelectionAvailability(
                    audioOptionCount: 0,
                    subtitleOptionCount: 0
                )
            ),
            canChange: true,
            selectAudioStream: { _ in },
            selectSubtitleStream: { _ in }
        )
        coordinator.updateQueueInsertion(
            for: secondSession,
            canAdd: true,
            isAdding: false
        )
        #expect(coordinator.canStop)
        #expect(coordinator.canChangeServerManagedMediaSelection)
        #expect(coordinator.canAddItemsToQueue)

        coordinator.clearPlaybackControls(for: firstSession)
        #expect(coordinator.canStop)
        #expect(coordinator.canChangeServerManagedMediaSelection)
        #expect(coordinator.canAddItemsToQueue)

        coordinator.clearPlaybackControls(for: secondSession)
        #expect(!coordinator.canStop)
        #expect(!coordinator.canChangeServerManagedMediaSelection)
        #expect(!coordinator.serverManagedMediaSelection.hasChoices)
        #expect(!coordinator.canAddItemsToQueue)
        #expect(!coordinator.isAddingToQueue)

        coordinator.updateCurrentPlayback(
            for: firstSession,
            presentation: firstPresentation
        )
        #expect(coordinator.currentPlayback?.item == secondItem)

        coordinator.updateCurrentPlayback(
            for: secondSession,
            presentation: refreshedSecondPresentation
        )
        #expect(coordinator.currentPlayback?.item == refreshedSecondItem)
        #expect(coordinator.presentation?.item == secondItem)
        #expect(coordinator.presentation?.id == "second-session")

        coordinator.close(secondSession)
        #expect(coordinator.currentPlayback == nil)
    }

    @Test func routePickerBindsTheExactPlayerAndRetainsItsAccessibleIdentity() {
        let routePickerView = AVRoutePickerView()
        let videoPlayer = AVPlayer()
        PlexPlaybackRoutePickerConfiguration.apply(
            to: routePickerView,
            player: videoPlayer
        )

        #expect(routePickerView.player === videoPlayer)
        #expect(routePickerView.accessibilityLabel()?.nilIfBlank != nil)

        let musicPlayer = AVPlayer()
        PlexPlaybackRoutePickerConfiguration.apply(
            to: routePickerView,
            player: musicPlayer
        )

        #expect(routePickerView.player === musicPlayer)
    }

    @Test func videoPreparationStageCoversOnlyThePrePlaybackVideoInterval() {
        #expect(PlexVideoPreparationPolicy.shouldPresent(
            mediaKind: .video,
            status: .idle,
            isLoading: true
        ))
        #expect(!PlexVideoPreparationPolicy.shouldPresent(
            mediaKind: .video,
            status: .idle,
            isLoading: false
        ))
        #expect(PlexVideoPreparationPolicy.shouldPresent(
            mediaKind: .video,
            status: .preparing,
            isLoading: false
        ))

        for status in [
            PlexPlaybackStatus.playing,
            .paused,
            .buffering,
            .ended,
            .failed("Unavailable"),
        ] {
            #expect(!PlexVideoPreparationPolicy.shouldPresent(
                mediaKind: .video,
                status: status,
                isLoading: true
            ))
        }

        #expect(!PlexVideoPreparationPolicy.shouldPresent(
            mediaKind: .music,
            status: .preparing,
            isLoading: true
        ))

    }

    @Test func nativePlayerSizingAcceptsOnlyFinitePositiveProposals() {
        #expect(PlexNativePlayerSizing.exactSize(for: ProposedViewSize(
            width: 1_000,
            height: 580
        )) == CGSize(width: 1_000, height: 580))
        #expect(PlexNativePlayerSizing.exactSize(for: ProposedViewSize(
            width: 1_000,
            height: nil
        )) == nil)
        #expect(PlexNativePlayerSizing.exactSize(for: ProposedViewSize(
            width: .infinity,
            height: 580
        )) == nil)
        #expect(PlexNativePlayerSizing.exactSize(for: ProposedViewSize(
            width: 0,
            height: 580
        )) == nil)
    }

    @Test func nativePlayerStageClaimsTheEntireAvailableContentRegion() {
        let recorder = PlexPlayerStageSizeRecorder()
        let hostingView = NSHostingView(rootView: VStack(spacing: 0) {
            PlexPlayerStage {
                PlexPlayerStageSizeProbe(recorder: recorder)
            }
            Color.clear
                .frame(height: 60)
        })
        hostingView.frame = CGRect(x: 0, y: 0, width: 1_000, height: 650)

        hostingView.layoutSubtreeIfNeeded()

        #expect(abs(recorder.size.width - 1_000) < 0.5)
        #expect(abs(recorder.size.height - 590) < 0.5)
    }

    @Test func coordinatorRunsOnlyAvailableNativeNavigationActions() {
        let coordinator = PlexPlayerCoordinator()
        var previousCount = 0
        var nextCount = 0
        coordinator.installNavigation(
            previous: { previousCount += 1 },
            next: { nextCount += 1 }
        )

        coordinator.goPrevious()
        coordinator.goNext()
        #expect(previousCount == 0)
        #expect(nextCount == 0)

        coordinator.updateNavigation(canGoPrevious: true, canGoNext: true)
        coordinator.goPrevious()
        coordinator.goNext()
        #expect(previousCount == 1)
        #expect(nextCount == 1)

        coordinator.clearNavigation()
        #expect(!coordinator.canGoPrevious)
        #expect(!coordinator.canGoNext)
    }

    @Test func seekPolicyUsesPlexTenSecondIntervalsAndClampsToMediaBounds() {
        #expect(PlexPlaybackSeek.skipInterval == 10)
        #expect(PlexPlaybackSkipDirection.backward.offset(for: 10) == -10)
        #expect(PlexPlaybackSkipDirection.forward.offset(for: 10) == 10)
        #expect(PlexPlaybackSkipDirection.forward.offset(for: 0) == nil)
        #expect(PlexPlaybackSkipDirection.backward.offset(for: .infinity) == nil)

        #expect(PlexPlaybackSeek.target(from: 5, duration: 120, offset: -10) == 0)
        #expect(PlexPlaybackSeek.target(from: 115, duration: 120, offset: 10) == 120)
        #expect(PlexPlaybackSeek.target(from: 40, duration: 120, offset: -10) == 30)
        #expect(PlexPlaybackSeek.target(from: 40, duration: 120, offset: 10) == 50)
        #expect(PlexPlaybackSeek.target(from: 40, duration: nil, offset: 10) == 50)
        #expect(PlexPlaybackSeek.clamped(-5, duration: 120) == 0)
        #expect(PlexPlaybackSeek.clamped(125, duration: 120) == 120)
        #expect(PlexPlaybackSeek.clamped(.nan, duration: 120) == 0)
    }

    @Test func rapidRelativeSeekReservationsAccumulateAndOnlyLatestCompletionWins() {
        var sequence = PlexPlaybackSeekSequence()

        let first = sequence.reserve(
            relativeOffset: 10,
            currentPosition: 40,
            duration: 120
        )
        let second = sequence.reserve(
            relativeOffset: 10,
            currentPosition: 40,
            duration: 120
        )
        let third = sequence.reserve(
            relativeOffset: -10,
            currentPosition: 40,
            duration: 120
        )

        #expect(first.target == 50)
        #expect(second.target == 60)
        #expect(third.target == 50)
        #expect(sequence.pendingTarget == 50)
        let firstDidFinish = sequence.finish(first)
        let secondDidFinish = sequence.finish(second)
        #expect(!firstDidFinish)
        #expect(!secondDidFinish)
        #expect(sequence.pendingTarget == 50)
        let thirdDidFinish = sequence.finish(third)
        #expect(thirdDidFinish)
        #expect(sequence.pendingTarget == nil)
    }

    @Test func absoluteSeekAndInvalidationRejectStaleCompletions() {
        var sequence = PlexPlaybackSeekSequence()
        let relative = sequence.reserve(
            relativeOffset: 10,
            currentPosition: 40,
            duration: 120
        )
        let absolute = sequence.reserve(
            absoluteTarget: 500,
            duration: 120
        )

        #expect(absolute.target == 120)
        let relativeDidFinish = sequence.finish(relative)
        #expect(!relativeDidFinish)

        sequence.invalidate()

        let absoluteDidFinish = sequence.finish(absolute)
        #expect(!absoluteDidFinish)
        #expect(sequence.pendingTarget == nil)
    }

    @Test func stoppedSessionEpochRejectsEveryOutstandingPlaybackOperation() {
        var epoch = PlexPlaybackSessionEpoch()

        #expect(epoch.currentTicket() == nil)
        let playback = epoch.activate()
        let queueTransition = epoch.currentTicket()

        #expect(epoch.isCurrent(playback))
        #expect(queueTransition.map(epoch.isCurrent) == true)

        epoch.invalidate()

        #expect(!epoch.isActive)
        #expect(!epoch.isCurrent(playback))
        #expect(queueTransition.map(epoch.isCurrent) == false)
        #expect(epoch.currentTicket() == nil)
    }

    @Test func restartedSessionEpochCannotReviveAnOperationFromThePriorSession() {
        var epoch = PlexPlaybackSessionEpoch()
        let priorSessionOperation = epoch.activate()

        epoch.invalidate()
        let restartedSessionOperation = epoch.activate()

        #expect(!epoch.isCurrent(priorSessionOperation))
        #expect(epoch.isCurrent(restartedSessionOperation))
        #expect(epoch.currentTicket() == restartedSessionOperation)
    }

    @Test func timelineResponseIdentityRequiresTheExactPlaybackSessionAndEpoch() {
        var epoch = PlexPlaybackSessionEpoch()
        let ticket = epoch.activate()
        let identity = PlexTimelineRequestIdentity(
            sessionIdentifier: "session-a",
            ticket: ticket
        )

        #expect(identity.isCurrent(sessionIdentifier: "session-a", epoch: epoch))
        #expect(!identity.isCurrent(sessionIdentifier: "session-b", epoch: epoch))

        epoch.invalidate()

        #expect(!identity.isCurrent(sessionIdentifier: "session-a", epoch: epoch))
    }

    @Test func timelineResponseFromThePriorEpochCannotAffectARestartedSession() {
        var epoch = PlexPlaybackSessionEpoch()
        let priorIdentity = PlexTimelineRequestIdentity(
            sessionIdentifier: "reused-session",
            ticket: epoch.activate()
        )

        epoch.invalidate()
        let restartedIdentity = PlexTimelineRequestIdentity(
            sessionIdentifier: "reused-session",
            ticket: epoch.activate()
        )

        #expect(!priorIdentity.isCurrent(sessionIdentifier: "reused-session", epoch: epoch))
        #expect(restartedIdentity.isCurrent(sessionIdentifier: "reused-session", epoch: epoch))
    }

    @Test func timelineReporterSerializesRequestsInSubmissionOrder() async throws {
        var events: [String] = []
        var releaseFirstReport: CheckedContinuation<Void, Never>?
        let reporter = PlexTimelineReportSequencer { update in
            events.append("start-\(update.time)")
            if update.time == 1_000 {
                await withCheckedContinuation { continuation in
                    releaseFirstReport = continuation
                }
            }
            events.append("finish-\(update.time)")
            return nil
        }
        let firstUpdate = PlexTimelineUpdate(
            ratingKey: "42",
            state: .playing,
            time: 1_000,
            duration: 10_000,
            sessionIdentifier: "session-a"
        )
        let secondUpdate = PlexTimelineUpdate(
            ratingKey: "42",
            state: .stopped,
            time: 2_000,
            duration: 10_000,
            sessionIdentifier: "session-a"
        )

        let first = Task { await reporter.report(firstUpdate) }
        for _ in 0..<20 where releaseFirstReport == nil {
            await Task.yield()
        }
        let firstReportContinuation = try #require(releaseFirstReport)

        let second = Task { await reporter.report(secondUpdate) }
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(events == ["start-1000"])

        firstReportContinuation.resume()
        _ = await (first.value, second.value)

        #expect(events == [
            "start-1000",
            "finish-1000",
            "start-2000",
            "finish-2000",
        ])
    }

    @Test func timelineReporterPreservesFinalStopAfterPeriodicCallerCancellation() async throws {
        var events: [String] = []
        var releasePlayingReport: CheckedContinuation<Void, Never>?
        let reporter = PlexTimelineReportSequencer { update in
            events.append("start-\(update.state.rawValue)")
            if update.state == .playing {
                await withCheckedContinuation { continuation in
                    releasePlayingReport = continuation
                }
            }
            events.append("finish-\(update.state.rawValue)")
            return nil
        }
        let playingUpdate = PlexTimelineUpdate(
            ratingKey: "42",
            state: .playing,
            time: 1_000,
            duration: 10_000,
            sessionIdentifier: "session-a"
        )
        let stoppedUpdate = PlexTimelineUpdate(
            ratingKey: "42",
            state: .stopped,
            time: 2_000,
            duration: 10_000,
            sessionIdentifier: "session-a"
        )

        let periodicCaller = Task { await reporter.report(playingUpdate) }
        for _ in 0..<20 where releasePlayingReport == nil {
            await Task.yield()
        }
        let playingReportContinuation = try #require(releasePlayingReport)

        periodicCaller.cancel()
        let finalStopCaller = Task { await reporter.report(stoppedUpdate) }
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(events == ["start-playing"])

        playingReportContinuation.resume()
        _ = await (periodicCaller.value, finalStopCaller.value)

        #expect(events == [
            "start-playing",
            "finish-playing",
            "start-stopped",
            "finish-stopped",
        ])
    }

    @Test func coordinatorRunsSeekCommandsOnlyForTheActiveSeekOwner() {
        let coordinator = PlexPlayerCoordinator()
        var offsets: [TimeInterval] = []

        coordinator.installSeeking(canSeek: false) { offset in
            offsets.append(offset)
        }
        coordinator.skipBackward()
        coordinator.skipForward()
        #expect(offsets.isEmpty)

        coordinator.updateSeeking(canSeek: true)
        coordinator.skipBackward()
        coordinator.skipForward()
        #expect(offsets == [-10, 10])

        coordinator.clearSeeking()
        coordinator.skipForward()
        #expect(!coordinator.canSeek)
        #expect(offsets == [-10, 10])
    }

    @Test func transportCommandsFollowTheActivePlaybackStateAndOwner() {
        let coordinator = PlexPlayerCoordinator()
        var toggleCount = 0
        var stopCount = 0

        coordinator.togglePlayback()
        coordinator.stopPlayback()
        #expect(coordinator.transportAction == nil)
        #expect(!coordinator.canStop)
        #expect(coordinator.playbackStatus == .idle)

        coordinator.installTransport(
            status: .paused,
            toggle: { toggleCount += 1 },
            stop: { stopCount += 1 }
        )
        #expect(coordinator.transportAction == .play)
        #expect(coordinator.canStop)
        #expect(coordinator.playbackStatus == .paused)

        coordinator.togglePlayback()
        #expect(toggleCount == 1)

        coordinator.updateTransport(status: .buffering)
        #expect(coordinator.transportAction == .pause)
        #expect(coordinator.playbackStatus == .buffering)
        coordinator.togglePlayback()
        #expect(toggleCount == 2)

        coordinator.updateTransport(status: .playing, canToggle: false)
        #expect(coordinator.playbackStatus == .playing)
        coordinator.togglePlayback()
        coordinator.stopPlayback()
        #expect(coordinator.transportAction == nil)
        #expect(toggleCount == 2)
        #expect(stopCount == 1)

        coordinator.clearTransport()
        coordinator.stopPlayback()
        #expect(!coordinator.canStop)
        #expect(coordinator.playbackStatus == .idle)
        #expect(stopCount == 1)
    }

    @Test func transportActionTreatsPreparationAndBufferingAsPauseableIntent() {
        #expect(PlexPlaybackTransportAction(status: .idle) == nil)
        #expect(PlexPlaybackTransportAction(status: .preparing) == .pause)
        #expect(PlexPlaybackTransportAction(status: .playing) == .pause)
        #expect(PlexPlaybackTransportAction(status: .buffering) == .pause)
        #expect(PlexPlaybackTransportAction(status: .paused) == .play)
        #expect(PlexPlaybackTransportAction(status: .ended) == nil)
        #expect(PlexPlaybackTransportAction(status: .failed("failed")) == nil)
    }

    @Test func playbackRateSelectionRequiresAnActiveOwner() {
        let coordinator = PlexPlayerCoordinator()
        var selections: [PlexPlaybackRate] = []

        coordinator.selectPlaybackRate(.double)
        #expect(selections.isEmpty)

        coordinator.installPlaybackRate(playbackRate: .normal) {
            selections.append($0)
        }
        #expect(coordinator.canChangePlaybackRate)
        #expect(coordinator.playbackRate == .normal)

        coordinator.selectPlaybackRate(.oneAndAHalf)
        #expect(selections == [.oneAndAHalf])

        coordinator.clearPlaybackRate()
        coordinator.selectPlaybackRate(.double)
        #expect(!coordinator.canChangePlaybackRate)
        #expect(coordinator.playbackRate == .normal)
        #expect(selections == [.oneAndAHalf])
    }

    @Test func videoQualitySelectionRequiresAChangeableVideoOwner() {
        let coordinator = PlexPlayerCoordinator()
        var selections: [PlexVideoQuality] = []

        coordinator.selectVideoQuality(.hd4Mbps)
        #expect(selections.isEmpty)

        coordinator.installVideoQuality(
            selection: PlexVideoQualitySelection(
                selectedQuality: .original,
                isVideo: true,
                canChange: false
            )
        ) {
            selections.append($0)
        }
        coordinator.selectVideoQuality(.hd4Mbps)
        #expect(selections.isEmpty)

        coordinator.installVideoQuality(
            selection: PlexVideoQualitySelection(
                selectedQuality: .original,
                isVideo: true,
                canChange: true
            )
        ) {
            selections.append($0)
        }
        coordinator.selectVideoQuality(.original)
        coordinator.selectVideoQuality(.hd4Mbps)
        #expect(selections == [.hd4Mbps])

        coordinator.clearVideoQuality()
        coordinator.selectVideoQuality(.fullHD8Mbps)
        #expect(!coordinator.videoQualitySelection.isVideo)
        #expect(selections == [.hd4Mbps])
    }

    @Test func serverManagedLanguageSelectionRequiresTheActiveExactChoice() throws {
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: Data(#"""
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
        """#.utf8))
        let selection = PlexServerManagedMediaSelection(
            selection: PlexPlaybackMediaSelection(
                item: item,
                source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
            ),
            nativeAvailability: PlexNativeMediaSelectionAvailability(
                audioOptionCount: 0,
                subtitleOptionCount: 0
            )
        )
        let coordinator = PlexPlayerCoordinator()
        var audioSelections: [Int] = []
        var subtitleSelections: [Int?] = []

        coordinator.installServerManagedMediaSelection(
            selection: selection,
            canChange: false,
            selectAudioStream: { audioSelections.append($0) },
            selectSubtitleStream: { subtitleSelections.append($0) }
        )
        coordinator.selectAudioStream(22)
        coordinator.selectSubtitleStream(nil)
        #expect(audioSelections.isEmpty)
        #expect(subtitleSelections.isEmpty)

        coordinator.updateServerManagedMediaSelection(
            selection: selection,
            canChange: true
        )
        coordinator.selectAudioStream(21)
        coordinator.selectAudioStream(999)
        coordinator.selectAudioStream(22)
        coordinator.selectSubtitleStream(31)
        coordinator.selectSubtitleStream(999)
        coordinator.selectSubtitleStream(nil)
        #expect(audioSelections == [22])
        #expect(subtitleSelections == [nil])

        coordinator.clearServerManagedMediaSelection()
        coordinator.selectAudioStream(22)
        coordinator.selectSubtitleStream(32)
        #expect(!coordinator.canChangeServerManagedMediaSelection)
        #expect(!coordinator.serverManagedMediaSelection.hasChoices)
        #expect(audioSelections == [22])
        #expect(subtitleSelections == [nil])
    }

    @Test func playbackReconfigurationPreservesPlayingAndPausedIntent() {
        for status in [
            PlexPlaybackStatus.preparing,
            .playing,
            .buffering,
        ] {
            let policy = PlexPlaybackReconfigurationPolicy(status: status)
            #expect(policy.canReload)
            #expect(policy.autoplay)
        }

        let pausedPolicy = PlexPlaybackReconfigurationPolicy(status: .paused)
        #expect(pausedPolicy.canReload)
        #expect(!pausedPolicy.autoplay)

        for status in [
            PlexPlaybackStatus.idle,
            .ended,
            .failed("Unavailable"),
        ] {
            let policy = PlexPlaybackReconfigurationPolicy(status: status)
            #expect(!policy.canReload)
            #expect(!policy.autoplay)
        }
    }

    @Test func playbackRecoveryIsExplicitAndLimitedToAnActiveFailedSession() {
        #expect(PlexPlaybackRecoveryPolicy.canRetry(
            status: .failed("Connection lost"),
            isLoading: false,
            isActive: true,
            didStop: false
        ))
        #expect(!PlexPlaybackRecoveryPolicy.canRetry(
            status: .playing,
            isLoading: false,
            isActive: true,
            didStop: false
        ))
        #expect(!PlexPlaybackRecoveryPolicy.canRetry(
            status: .failed("Connection lost"),
            isLoading: true,
            isActive: true,
            didStop: false
        ))
        #expect(!PlexPlaybackRecoveryPolicy.canRetry(
            status: .failed("Connection lost"),
            isLoading: false,
            isActive: false,
            didStop: false
        ))
        #expect(!PlexPlaybackRecoveryPolicy.canRetry(
            status: .failed("Connection lost"),
            isLoading: false,
            isActive: true,
            didStop: true
        ))
    }

    @Test func failedNativePlayerRequiresReplacementButFailedItemDoesNotImplyIt() {
        #expect(PlexNativePlayerRecoveryPolicy.requiresReplacement(status: .failed))
        #expect(!PlexNativePlayerRecoveryPolicy.requiresReplacement(status: .unknown))
        #expect(!PlexNativePlayerRecoveryPolicy.requiresReplacement(status: .readyToPlay))
    }

    @Test func playbackRecoveryPreservesTheExactSessionDecisionContext() throws {
        let plan = PlexPlaybackPlan(
            url: try #require(URL(string: "https://plex.example/recover.m3u8")),
            method: .directStream,
            mediaKind: .video,
            sessionIdentifier: "old-session",
            ratingKey: "42",
            duration: 7_200,
            startTime: 0,
            source: PlexPlaybackSource(mediaIndex: 2, partIndex: -1),
            usesServerMediaSelection: true
        )

        let request = PlexPlaybackRecoveryRequest(
            plan: plan,
            videoQuality: .fullHD8Mbps,
            position: 1_234.567
        )

        #expect(request.source == PlexPlaybackSource(mediaIndex: 2, partIndex: -1))
        #expect(request.videoQuality == .fullHD8Mbps)
        #expect(request.startTime == 1_234.567)
        #expect(request.forceServerMediaSelection)

        let invalidPositionRequest = PlexPlaybackRecoveryRequest(
            plan: plan,
            videoQuality: .original,
            position: .nan
        )
        #expect(invalidPositionRequest.startTime == 0)
    }

    @Test func shuffleChangesRequireAnAvailableOwnerAndRemainServerConfirmed() {
        let coordinator = PlexPlayerCoordinator()
        var selections: [Bool] = []

        coordinator.setShuffled(true)
        #expect(selections.isEmpty)

        coordinator.installShuffle(isShuffled: false, canChange: true) {
            selections.append($0)
        }
        coordinator.setShuffled(true)
        #expect(selections == [true])
        #expect(!coordinator.isShuffled)

        coordinator.updateShuffle(isShuffled: true, canChange: true)
        #expect(coordinator.isShuffled)
        coordinator.setShuffled(true)
        #expect(selections == [true])

        coordinator.clearShuffle()
        coordinator.setShuffled(false)
        #expect(!coordinator.canChangeShuffle)
        #expect(!coordinator.isShuffled)
        #expect(selections == [true])
    }

    @Test func repeatModeSelectionRequiresAnOwnerAndRejectsUnavailableRepeatAll() {
        let coordinator = PlexPlayerCoordinator()
        var selections: [PlexPlaybackRepeatMode] = []

        coordinator.selectRepeatMode(.one)
        #expect(selections.isEmpty)

        coordinator.installRepeatMode(repeatMode: .off, canRepeatAll: false) {
            selections.append($0)
        }
        coordinator.selectRepeatMode(.all)
        #expect(selections.isEmpty)

        coordinator.selectRepeatMode(.one)
        #expect(selections == [.one])
        #expect(coordinator.repeatMode == .off)

        coordinator.updateRepeatMode(repeatMode: .one, canRepeatAll: true)
        coordinator.selectRepeatMode(.all)
        #expect(selections == [.one, .all])

        coordinator.clearRepeatMode()
        coordinator.selectRepeatMode(.one)
        #expect(!coordinator.canChangeRepeatMode)
        #expect(!coordinator.canRepeatAll)
        #expect(coordinator.repeatMode == .off)
        #expect(selections == [.one, .all])
    }

    @Test func completionPolicyMatchesNativeRepeatSemantics() {
        #expect(PlexPlaybackCompletionAction.resolve(
            repeatMode: .off,
            canAdvance: false,
            canResetQueue: false
        ) == .stop)
        #expect(PlexPlaybackCompletionAction.resolve(
            repeatMode: .off,
            canAdvance: true,
            canResetQueue: true
        ) == .advanceNext)
        #expect(PlexPlaybackCompletionAction.resolve(
            repeatMode: .one,
            canAdvance: true,
            canResetQueue: true
        ) == .replayCurrent)
        #expect(PlexPlaybackCompletionAction.resolve(
            repeatMode: .all,
            canAdvance: true,
            canResetQueue: true
        ) == .advanceNext)
        #expect(PlexPlaybackCompletionAction.resolve(
            repeatMode: .all,
            canAdvance: false,
            canResetQueue: true
        ) == .resetQueue)
        #expect(PlexPlaybackCompletionAction.resolve(
            repeatMode: .all,
            canAdvance: false,
            canResetQueue: false
        ) == .stop)
    }

    @Test func playbackRateConfiguresAVPlayerWithoutStartingIdlePlayback() {
        let engine = PlexPlaybackEngine()

        engine.setPlaybackRate(.oneAndAHalf)
        #expect(engine.playbackRate == .oneAndAHalf)
        #expect(engine.player.defaultRate == PlexPlaybackRate.oneAndAHalf.rawValue)
        #expect(engine.player.rate == 0)

        engine.stop()
        #expect(engine.playbackRate == .oneAndAHalf)
        #expect(engine.player.defaultRate == PlexPlaybackRate.oneAndAHalf.rawValue)
        #expect(engine.player.rate == 0)
    }

    @Test func nativePlayerSpeedControlUsesTheExactSessionRates() {
        let player = AVPlayer()
        let playerView = AVPlayerView()
        playerView.player = player

        PlexNativePlaybackSpeedConfiguration.apply(
            to: playerView,
            playbackRate: .oneAndAQuarter
        )

        #expect(playerView.speeds.map(\.rate) == PlexPlaybackRate.allCases.map(\.rawValue))
        #expect(playerView.selectedSpeed?.rate == PlexPlaybackRate.oneAndAQuarter.rawValue)
        #expect(player.defaultRate == PlexPlaybackRate.oneAndAQuarter.rawValue)
        #expect(player.rate == 0)
    }

    @Test func nativePlayerSpeedsRoundTripOnlySupportedSessionRates() {
        for playbackRate in PlexPlaybackRate.allCases {
            let speed = PlexNativePlaybackSpeedConfiguration.speed(for: playbackRate)
            #expect(speed?.localizedName == playbackRate.label)
            #expect(
                PlexNativePlaybackSpeedConfiguration.playbackRate(for: speed)
                    == playbackRate
            )
        }

        let unsupportedSpeed = AVPlaybackSpeed(rate: 1.1, localizedName: "1.1×")
        #expect(
            PlexNativePlaybackSpeedConfiguration.playbackRate(for: unsupportedSpeed) == nil
        )
        #expect(PlexNativePlaybackSpeedConfiguration.playbackRate(for: nil) == nil)
    }

    @Test func playbackRatesRoundTripOnlySupportedRemoteCommandValues() {
        #expect(PlexPlaybackRate.allCases.map(\.rawValue) == [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2])
        for playbackRate in PlexPlaybackRate.allCases {
            #expect(
                PlexPlaybackRate(remoteCommandValue: playbackRate.rawValue) == playbackRate
            )
        }
        #expect(PlexPlaybackRate(remoteCommandValue: 1.1) == nil)
    }

    @Test func fullScreenLifecycleKeepsPlaybackAliveUntilTheWindowFinishesExiting() {
        let lifecycle = PlexPlayerPresentationLifecycle()

        #expect(!lifecycle.keepsPlaybackAliveWhenViewDisappears)
        lifecycle.willEnterFullScreen()
        #expect(lifecycle.isFullScreenActive)
        #expect(lifecycle.keepsPlaybackAliveWhenViewDisappears)

        lifecycle.didExitFullScreen()
        #expect(!lifecycle.isFullScreenActive)
        #expect(!lifecycle.keepsPlaybackAliveWhenViewDisappears)
    }

    @Test func pictureInPictureLifecycleCoversFailureAndNormalStop() {
        let lifecycle = PlexPlayerPresentationLifecycle()

        lifecycle.willStartPictureInPicture()
        #expect(lifecycle.isPictureInPictureActive)
        #expect(lifecycle.keepsPlaybackAliveWhenViewDisappears)

        lifecycle.failedToStartPictureInPicture()
        #expect(!lifecycle.isPictureInPictureActive)
        #expect(!lifecycle.keepsPlaybackAliveWhenViewDisappears)

        lifecycle.willStartPictureInPicture()
        lifecycle.didStopPictureInPicture()
        #expect(!lifecycle.isPictureInPictureActive)
        #expect(!lifecycle.keepsPlaybackAliveWhenViewDisappears)
    }

    @Test func presentationModesRemainIndependentWhenTransitionsOverlap() {
        let lifecycle = PlexPlayerPresentationLifecycle()

        lifecycle.willEnterFullScreen()
        lifecycle.willStartPictureInPicture()
        lifecycle.didExitFullScreen()

        #expect(!lifecycle.isFullScreenActive)
        #expect(lifecycle.isPictureInPictureActive)
        #expect(lifecycle.keepsPlaybackAliveWhenViewDisappears)

        lifecycle.didStopPictureInPicture()
        #expect(!lifecycle.keepsPlaybackAliveWhenViewDisappears)
    }
}

private func playbackPlan(
    sessionIdentifier: String,
    ratingKey: String
) -> PlexPlaybackPlan {
    PlexPlaybackPlan(
        url: URL(fileURLWithPath: "/tmp/plexbar-\(sessionIdentifier).mp4"),
        method: .directPlay,
        mediaKind: .video,
        sessionIdentifier: sessionIdentifier,
        ratingKey: ratingKey,
        duration: 120,
        startTime: 0,
        source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
        usesServerMediaSelection: false
    )
}

@MainActor
private final class PlexPlayerStageSizeRecorder {
    var size = CGSize.zero
}

private struct PlexPlayerStageSizeProbe: NSViewRepresentable {
    let recorder: PlexPlayerStageSizeRecorder

    func makeNSView(context: Context) -> NSView {
        PlexPlayerStageProbeNSView(recorder: recorder)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class PlexPlayerStageProbeNSView: NSView {
    private let recorder: PlexPlayerStageSizeRecorder

    init(recorder: PlexPlayerStageSizeRecorder) {
        self.recorder = recorder
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recorder.size = newSize
    }
}
