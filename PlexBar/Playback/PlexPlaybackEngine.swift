import AVFoundation
import Observation

enum PlexNativePlayerRecoveryPolicy {
    static func requiresReplacement(status: AVPlayer.Status) -> Bool {
        status == .failed
    }
}

enum PlexPlaybackStatus: Equatable, Sendable {
    case idle
    case preparing
    case playing
    case paused
    case buffering
    case ended
    case failed(String)
}

enum PlexPlaybackWaitingReason: Equatable, Sendable {
    case minimizingStalls
    case evaluatingBufferingRate
    case noItemToPlay
    case coordinatedPlayback
    case interstitialEvent

    init?(
        timeControlStatus: AVPlayer.TimeControlStatus,
        nativeReason: AVPlayer.WaitingReason?
    ) {
        guard timeControlStatus == .waitingToPlayAtSpecifiedRate,
              let nativeReason else {
            return nil
        }

        if nativeReason == .toMinimizeStalls {
            self = .minimizingStalls
        } else if nativeReason == .evaluatingBufferingRate {
            self = .evaluatingBufferingRate
        } else if nativeReason == .noItemToPlay {
            self = .noItemToPlay
        } else if nativeReason == .waitingForCoordinatedPlayback {
            self = .coordinatedPlayback
        } else if nativeReason == .interstitialEvent {
            self = .interstitialEvent
        } else {
            return nil
        }
    }

    var diagnosticLabel: String? {
        switch self {
        case .minimizingStalls:
            "Minimizing Stalls"
        case .evaluatingBufferingRate:
            nil
        case .noItemToPlay:
            "No Item to Play"
        case .coordinatedPlayback:
            "Coordinated Playback"
        case .interstitialEvent:
            "Interstitial Event"
        }
    }
}

enum PlexPlaybackTransportAction: Equatable, Sendable {
    case play
    case pause

    init?(status: PlexPlaybackStatus) {
        switch status {
        case .preparing, .playing, .buffering:
            self = .pause
        case .paused:
            self = .play
        case .idle, .ended, .failed:
            return nil
        }
    }
}

@MainActor
@Observable
final class PlexPlaybackEngine {
    private(set) var status: PlexPlaybackStatus = .idle
    private(set) var waitingReason: PlexPlaybackWaitingReason?
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval?
    private(set) var mediaFacts: PlexNativeMediaFacts?
    private(set) var metricFacts: PlexPlaybackMetricFacts?
    private(set) var playbackRate: PlexPlaybackRate = .normal
    private(set) var unexpectedTimeJumpRevision: UInt = 0

    private(set) var player = AVPlayer()
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var endObservationTask: Task<Void, Never>?
    @ObservationIgnored private var timeJumpObservationTask: Task<Void, Never>?
    @ObservationIgnored private var mediaInspectionTask: Task<Void, Never>?
    @ObservationIgnored private var metricsTask: Task<Void, Never>?
    @ObservationIgnored private var inspectedItemIdentifier: ObjectIdentifier?
    @ObservationIgnored private var pendingStartTime: TimeInterval?
    @ObservationIgnored private var autoplayAfterPendingSeek = true
    @ObservationIgnored private var seekSequence = PlexPlaybackSeekSequence()
    @ObservationIgnored private var expectedTimeJumps = PlexPlaybackTimeJumpExpectations()

    func load(plan: PlexPlaybackPlan, autoplay: Bool = true) async throws {
        let playerRequiresReplacement = PlexNativePlayerRecoveryPolicy.requiresReplacement(
            status: player.status
        )
        stop()
        if playerRequiresReplacement {
            player = AVPlayer()
        }
        updateWaitingReason(nil)
        status = .preparing

        let asset = AVURLAsset(url: plan.url)
        let item = AVPlayerItem(asset: asset)
        player.preventsDisplaySleepDuringVideoPlayback = plan.mediaKind == .video
        player.defaultRate = playbackRate.rawValue
        player.replaceCurrentItem(with: item)
        duration = plan.duration
        pendingStartTime = plan.startTime > 0 ? plan.startTime : nil
        autoplayAfterPendingSeek = autoplay
        observeEnd(of: item)
        observeTimeJumps(of: item)
        observeMetrics(
            of: item,
            playbackMethod: plan.method,
            mediaKind: plan.mediaKind
        )
        startMonitoring()
        if autoplay {
            player.play()
        } else {
            player.pause()
            status = .paused
        }
    }

    func play() {
        autoplayAfterPendingSeek = true
        player.defaultRate = playbackRate.rawValue
        player.play()
        updateWaitingReason(nil)
        status = .playing
    }

    func pause() {
        autoplayAfterPendingSeek = false
        player.pause()
        updateWaitingReason(nil)
        status = .paused
    }

    func setPlaybackRate(_ playbackRate: PlexPlaybackRate) {
        guard self.playbackRate != playbackRate else {
            return
        }

        self.playbackRate = playbackRate
        player.defaultRate = playbackRate.rawValue
        switch status {
        case .preparing, .playing, .buffering:
            player.play()
        case .idle, .paused, .ended, .failed:
            break
        }
    }

    func reserveSeek(to position: TimeInterval) -> PlexPlaybackSeekSequence.Request {
        seekSequence.reserve(absoluteTarget: position, duration: duration)
    }

    func reserveSkip(
        by offset: TimeInterval,
        duration: TimeInterval?
    ) -> PlexPlaybackSeekSequence.Request {
        seekSequence.reserve(
            relativeOffset: offset,
            currentPosition: position,
            duration: duration ?? self.duration
        )
    }

    func performSeek(_ request: PlexPlaybackSeekSequence.Request) async -> Bool {
        guard seekSequence.isCurrent(request) else {
            return false
        }
        let item = player.currentItem
        let timeJumpToken = expectedTimeJumps.expect(target: request.target)
        let completed = await player.seek(
            to: CMTime(seconds: request.target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        guard completed, player.currentItem === item else {
            expectedTimeJumps.cancel(timeJumpToken)
            return false
        }
        guard seekSequence.finish(request) else {
            return false
        }
        position = request.target
        return true
    }

    @discardableResult
    func seek(to position: TimeInterval) async -> Bool {
        let request = reserveSeek(to: position)
        return await performSeek(request)
    }

    func cancelPendingSeek() {
        player.currentItem?.cancelPendingSeeks()
        seekSequence.invalidate()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        endObservationTask?.cancel()
        endObservationTask = nil
        timeJumpObservationTask?.cancel()
        timeJumpObservationTask = nil
        mediaInspectionTask?.cancel()
        mediaInspectionTask = nil
        metricsTask?.cancel()
        metricsTask = nil
        inspectedItemIdentifier = nil
        seekSequence.invalidate()
        expectedTimeJumps.invalidate()
        player.pause()
        player.replaceCurrentItem(with: nil)
        player.preventsDisplaySleepDuringVideoPlayback = false
        position = 0
        duration = nil
        mediaFacts = nil
        updateMetricFacts(nil)
        pendingStartTime = nil
        autoplayAfterPendingSeek = true
        updateWaitingReason(nil)
        status = .idle
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshState()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        endObservationTask?.cancel()
        endObservationTask = Task { [weak self, weak item] in
            guard let item else {
                return
            }
            for await _ in NotificationCenter.default.notifications(
                named: AVPlayerItem.didPlayToEndTimeNotification,
                object: item
            ) {
                guard !Task.isCancelled else {
                    return
                }
                if let duration = self?.duration {
                    self?.position = duration
                }
                self?.updateWaitingReason(nil)
                self?.status = .ended
            }
        }
    }

    private func observeTimeJumps(of item: AVPlayerItem) {
        timeJumpObservationTask?.cancel()
        timeJumpObservationTask = Task { [weak self, weak item] in
            guard let item else {
                return
            }

            for await _ in NotificationCenter.default.notifications(
                named: AVPlayerItem.timeJumpedNotification,
                object: item
            ) {
                guard !Task.isCancelled,
                      let self,
                      player.currentItem === item else {
                    return
                }

                let currentSeconds = player.currentTime().seconds
                guard currentSeconds.isFinite else {
                    continue
                }
                let currentPosition = max(currentSeconds, 0)
                position = currentPosition
                guard !expectedTimeJumps.consume(position: currentPosition) else {
                    continue
                }
                unexpectedTimeJumpRevision &+= 1
            }
        }
    }

    private func inspectMediaIfNeeded(of item: AVPlayerItem) {
        let itemIdentifier = ObjectIdentifier(item)
        guard inspectedItemIdentifier != itemIdentifier else {
            return
        }
        inspectedItemIdentifier = itemIdentifier
        mediaInspectionTask?.cancel()
        mediaInspectionTask = Task { [weak self, weak item] in
            guard let self, let item else {
                return
            }

            let facts = await PlexNativeMediaInspector.inspect(item: item)
            guard !Task.isCancelled, player.currentItem === item else {
                return
            }
            mediaFacts = facts
        }
    }

    private func observeMetrics(
        of item: AVPlayerItem,
        playbackMethod: PlexPlaybackPlan.Method,
        mediaKind: PlexPlaybackMediaKind
    ) {
        metricsTask?.cancel()
        updateMetricFacts(nil)
        metricsTask = Task { [weak self, weak item] in
            guard let item else {
                return
            }

            let metrics = item.metrics(forType: AVMetricPlayerItemStallEvent.self)
                .chronologicalMerge(
                    with: item.metrics(
                        forType: AVMetricPlayerItemInitialLikelyToKeepUpEvent.self
                    ),
                    item.metrics(forType: AVMetricPlayerItemVariantSwitchEvent.self)
                    , item.metrics(forType: AVMetricHLSMediaSegmentRequestEvent.self)
                    , item.metrics(forType: AVMetricMediaResourceRequestEvent.self)
                )
            var facts = PlexPlaybackMetricFacts()

            do {
                for try await (event, publisher) in metrics {
                    guard !Task.isCancelled,
                          let self,
                          let publishedItem = publisher as? AVPlayerItem,
                          publishedItem === item,
                          player.currentItem === item else {
                        return
                    }

                    switch event {
                    case is AVMetricPlayerItemStallEvent:
                        facts.recordStall()
                    case let event as AVMetricPlayerItemInitialLikelyToKeepUpEvent:
                        facts.recordInitialLikelyToKeepUp(
                            timeTaken: event.timeTaken,
                            variant: PlexPlaybackVariantFacts(variant: event.variant)
                        )
                    case let event as AVMetricPlayerItemVariantSwitchEvent:
                        facts.recordVariantSwitch(
                            succeeded: event.didSucceed,
                            to: PlexPlaybackVariantFacts(variant: event.toVariant)
                        )
                    case let event as AVMetricHLSMediaSegmentRequestEvent:
                        guard playbackMethod != .directPlay, mediaKind == .video else {
                            continue
                        }
                        let sample = PlexPlaybackBandwidthSample(segment: event)
                        facts.recordBandwidthSample(sample)
                    case let event as AVMetricMediaResourceRequestEvent:
                        guard playbackMethod == .directPlay, mediaKind == .video else {
                            continue
                        }
                        let sample = PlexPlaybackBandwidthSample(resourceRequest: event)
                        facts.recordBandwidthSample(sample)
                    default:
                        continue
                    }
                    updateMetricFacts(facts)
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func updateMetricFacts(_ metricFacts: PlexPlaybackMetricFacts?) {
        guard self.metricFacts != metricFacts else {
            return
        }
        self.metricFacts = metricFacts
    }

    private func refreshState() {
        if player.status == .failed {
            updateWaitingReason(nil)
            status = .failed(
                player.error?.localizedDescription
                    ?? "macOS could no longer play this stream."
            )
            return
        }

        let currentSeconds = player.currentTime().seconds
        if currentSeconds.isFinite {
            position = max(currentSeconds, 0)
        }

        guard let item = player.currentItem else {
            updateWaitingReason(nil)
            status = .idle
            return
        }

        guard refreshItemState(item) else {
            return
        }

        if let startTime = pendingStartTime {
            pendingStartTime = nil
            Task { [weak self, weak item] in
                guard let self, let item else {
                    return
                }
                let completed = await seek(to: startTime)
                guard completed, player.currentItem === item else {
                    return
                }
                if autoplayAfterPendingSeek {
                    play()
                } else {
                    pause()
                }
            }
        }

        refreshTimeControlState()
    }

    private func refreshItemState(_ item: AVPlayerItem) -> Bool {
        if let error = item.error {
            updateWaitingReason(nil)
            status = .failed(error.localizedDescription)
            return false
        }

        let itemDuration = item.duration.seconds
        if itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }

        switch item.status {
        case .unknown:
            updateWaitingReason(nil)
            if status != .paused {
                status = .preparing
            }
            return false
        case .failed:
            updateWaitingReason(nil)
            status = .failed(item.error?.localizedDescription ?? "macOS could not open the Plex stream.")
            return false
        case .readyToPlay:
            inspectMediaIfNeeded(of: item)
            return true
        @unknown default:
            return true
        }
    }

    private func refreshTimeControlState() {
        updateWaitingReason(PlexPlaybackWaitingReason(
            timeControlStatus: player.timeControlStatus,
            nativeReason: player.reasonForWaitingToPlay
        ))

        switch player.timeControlStatus {
        case .paused:
            if status != .preparing, status != .ended {
                status = .paused
            }
        case .waitingToPlayAtSpecifiedRate:
            status = .buffering
        case .playing:
            status = .playing
        @unknown default:
            break
        }
    }

    private func updateWaitingReason(_ waitingReason: PlexPlaybackWaitingReason?) {
        guard self.waitingReason != waitingReason else {
            return
        }
        self.waitingReason = waitingReason
    }
}
