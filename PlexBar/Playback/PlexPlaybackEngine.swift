import PlexClientKit
import AVFoundation
import Observation

enum PlexNativePlayerRecoveryPolicy {
    static func requiresReplacement(status: AVPlayer.Status) -> Bool {
        status == .failed
    }
}

@MainActor
@Observable
final class PlexPlaybackEngine {
    var isPreparingInitialPosition: Bool { pendingStartTime != nil }

    private(set) var status: PlexPlaybackStatus = .idle
    private(set) var waitingReason: PlexPlaybackWaitingReason?
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval?
    private(set) var mediaFacts: PlexNativeMediaFacts?
    private(set) var metricFacts: PlexPlaybackMetricFacts?
    private(set) var playbackRate: PlexPlaybackRate = .normal
    private(set) var unexpectedTimeJumpRevision: UInt = 0

    private(set) var player: AVPlayer
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var endObservationTask: Task<Void, Never>?
    @ObservationIgnored private var timeJumpObservationTask: Task<Void, Never>?
    @ObservationIgnored private var mediaInspectionTask: Task<Void, Never>?
    @ObservationIgnored private var metricsTask: Task<Void, Never>?
    @ObservationIgnored private var inspectedItemIdentifier: ObjectIdentifier?
    private var pendingStartTime: TimeInterval?
    @ObservationIgnored private var initialSeekTask: Task<Void, Never>?
    @ObservationIgnored private var autoplayAfterPendingSeek = true
    @ObservationIgnored private var seekSequence = PlexPlaybackSeekSequence()
    @ObservationIgnored private var expectedTimeJumps = PlexPlaybackTimeJumpExpectations()

    init(player: AVPlayer = AVPlayer()) {
        self.player = player
    }

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
        position = pendingStartTime ?? 0
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
            play()
        } else {
            pause()
        }
    }

    func play() {
        autoplayAfterPendingSeek = true
        player.defaultRate = playbackRate.rawValue
        // A play command records intent while the initial position is pending.
        // Only a successful seek may release playback from that position.
        guard pendingStartTime == nil else {
            player.pause()
            if case .failed = status { return }
            status = .preparing
            return
        }
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
        guard pendingStartTime == nil else { return }
        switch status {
        case .preparing, .playing, .buffering:
            player.play()
        case .idle, .paused, .ended, .failed:
            break
        }
    }

    func reserveSeek(to position: TimeInterval) -> PlexPlaybackSeekSequence.Request {
        let request = seekSequence.reserve(absoluteTarget: position, duration: duration)
        updatePendingInitialPosition(for: request)
        return request
    }

    func reserveSkip(
        by offset: TimeInterval,
        duration: TimeInterval?
    ) -> PlexPlaybackSeekSequence.Request {
        let request = seekSequence.reserve(
            relativeOffset: offset,
            currentPosition: position,
            duration: duration ?? self.duration
        )
        updatePendingInitialPosition(for: request)
        return request
    }

    private func updatePendingInitialPosition(for request: PlexPlaybackSeekSequence.Request) {
        guard pendingStartTime != nil else { return }
        pendingStartTime = request.target
        position = request.target
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
        guard player.currentItem === item, seekSequence.isCurrent(request) else {
            expectedTimeJumps.cancel(timeJumpToken)
            return false
        }
        guard completed else {
            expectedTimeJumps.cancel(timeJumpToken)
            if pendingStartTime != nil {
                player.pause()
                updateWaitingReason(nil)
                status = .failed("macOS could not resume this stream at the saved position.")
            }
            return false
        }
        guard seekSequence.finish(request) else {
            return false
        }
        position = request.target
        if pendingStartTime != nil {
            pendingStartTime = nil
            if autoplayAfterPendingSeek { play() } else { pause() }
        }
        return true
    }

    @discardableResult
    func seek(to position: TimeInterval) async -> Bool {
        let request = reserveSeek(to: position)
        return await performSeek(request)
    }

    func cancelPendingSeek() {
        seekSequence.invalidate()
        initialSeekTask?.cancel()
        initialSeekTask = nil
        player.currentItem?.cancelPendingSeeks()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        initialSeekTask?.cancel()
        initialSeekTask = nil
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
                if pendingStartTime == nil { position = currentPosition }
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
        if case .failed = status { return }
        if player.status == .failed {
            updateWaitingReason(nil)
            status = .failed(
                player.error?.localizedDescription
                    ?? "macOS could no longer play this stream."
            )
            return
        }

        let currentSeconds = player.currentTime().seconds
        if pendingStartTime == nil, currentSeconds.isFinite {
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
            // Reserve synchronously so a newer user seek wins even if this task
            // has not started yet. Retain the target for reporting and recovery.
            if initialSeekTask == nil, seekSequence.pendingTarget == nil {
                let request = reserveSeek(to: startTime)
                initialSeekTask = Task { [weak self, weak item] in
                    guard !Task.isCancelled, let self, let item,
                          player.currentItem === item else { return }
                    _ = await performSeek(request)
                    guard player.currentItem === item else { return }
                    initialSeekTask = nil
                }
            }
            return
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
