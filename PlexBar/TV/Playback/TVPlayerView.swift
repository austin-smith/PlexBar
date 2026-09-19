import PlexClientKit
import PlexModels
import AVFoundation
import AVKit
@preconcurrency import MediaPlayer
import Observation
import SwiftUI
import UIKit

struct TVPlayerView: View {
    @Environment(TVAppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let request: TVPlexPlaybackRequest

    @State private var session = TVPlaybackSession()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = session.player {
                TVNativePlayerController(
                    player: player,
                    store: store,
                    mediaKind: session.playbackMediaKind,
                    selectedVideoQuality: session.selectedVideoQuality
                        ?? store.activeVideoQuality,
                    selectedMusicQuality: session.selectedMusicQuality
                        ?? store.activeMusicQuality,
                    selectedAudioBoost: session.selectedAudioBoost
                        ?? store.audioBoost,
                    selectedSubtitleSize: store.subtitleSize,
                    automaticallySyncsSubtitles: store.automaticallySyncSubtitles,
                    automaticallyAdjustsVideoQuality: store.automaticallyAdjustVideoQuality,
                    videoConversionControl: videoConversionControl,
                    selectedVideoScalingMode: store.videoScalingMode,
                    showsVideoQualityMenu: session.isVideoPlayback,
                    showsMusicQualityMenu: session.isMusicPlayback
                        && store.connection?.kind != .local,
                    showsAudioBoostMenu: session.supportsAudioBoost,
                    showsSubtitleSizeMenu: session.hasAvailableSubtitles,
                    showsSubtitleAutoSyncAction: session.supportsSubtitleAutoSync,
                    subtitleOffsetSelection: session.subtitleOffsetSelection,
                    playbackVersionSelection: session.playbackVersionSelection,
                    mediaSelection: session.serverManagedMediaSelection,
                    audioPresentation: session.audioPresentation,
                    canChangeMediaSelection: !session.isReconfiguringMediaSelection
                        && !session.isNavigatingQueue
                        && !session.isMutatingQueue
                        && !session.isReplacingPlayback
                        && !session.isPreparingInitialPosition,
                    playbackInfo: session.playbackInfo,
                    queuePresentation: session.queuePresentation,
                    markerAction: session.activeMarkerAction,
                    availableMarkerKinds: session.availableMarkerKinds,
                    markerPreferences: store.playbackMarkerPreferences,
                    canGoPrevious: session.canGoPrevious,
                    canGoNext: session.canGoNext,
                    previousItemTitle: session.previousItemTitle,
                    nextItemTitle: session.nextItemTitle,
                    canChangeShuffle: session.canChangeShuffle,
                    isShuffled: session.isShuffled,
                    repeatMode: session.repeatMode,
                    canRepeatAll: session.canRepeatAll,
                    sleepTimer: store.playbackSleepTimer,
                    selectVideoQuality: session.selectVideoQuality,
                    selectMusicQuality: session.selectMusicQuality,
                    selectAudioBoost: session.selectAudioBoost,
                    selectSubtitleSize: session.selectSubtitleSize,
                    setSubtitleAutoSync: session.setSubtitleAutoSync,
                    setSubtitleOffset: session.setSubtitleOffset,
                    setVideoConversionForced: session.setVideoConversionForced,
                    selectPlaybackVersion: session.selectPlaybackVersion,
                    selectVideoScalingMode: store.selectVideoScalingMode,
                    selectAudioStream: session.selectAudioStream,
                    selectSubtitleStream: session.selectSubtitleStream,
                    restartFromBeginning: session.restartFromBeginning,
                    playPreviousItem: session.playPreviousItem,
                    playNextItem: session.playNextItem,
                    playQueuedItem: session.playQueuedItem,
                    moveQueuedItem: session.moveQueuedItem,
                    removeQueuedItem: session.removeQueuedItem,
                    setShuffled: session.setShuffled,
                    setRepeatMode: session.setRepeatMode,
                    setSleepTimer: { preset in
                        session.setSleepTimer(preset, store: store)
                    },
                    setMarkerBehavior: store.setPlaybackMarkerBehavior,
                    skipMarker: session.skipActiveMarker,
                    shouldPresentContentProposal: session.shouldPresentContentProposal,
                    acceptContentProposal: session.acceptContentProposal,
                    rejectContentProposal: session.rejectContentProposal,
                    shouldHandlePlayPausePress: session.shouldHandleNativePlayPausePress,
                    handlePlayPausePress: session.handleNativePlayPausePress,
                    recordInteraction: session.recordUserInteraction
                )
                    .ignoresSafeArea()

                if let nextItem = session.upNextItem {
                    TVPostPlayOverlay(
                        item: nextItem,
                        title: session.postPlayTitle,
                        countdown: session.postPlayCountdown,
                        playNow: session.playNextNow,
                        cancel: session.cancelPostPlay
                    )
                    .transition(.opacity)
                }
            } else if let errorMessage = session.errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Play", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(errorMessage)
                } actions: {
                    if session.canRetryPlayback {
                        Button("Try Again", systemImage: "arrow.clockwise") {
                            Task { await session.retry(request: request, store: store) }
                        }
                    }
                    Button("Close", role: .cancel, action: store.dismissPlayer)
                }
            } else {
                VStack(spacing: 26) {
                    ProgressView()
                        .controlSize(.extraLarge)
                    Text("Preparing \(request.item.title)…")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: request.id) {
            await session.prepare(request: request, store: store)
        }
        .animation(
            PlexMotion.surfaceAnimation(reduceMotion: accessibilityReduceMotion),
            value: session.upNextItem?.id
        )
        .alert("Couldn’t Change Playback", isPresented: Binding(
            get: { session.mediaSelectionErrorMessage != nil },
            set: { if !$0 { session.dismissMediaSelectionError() } }
        )) {
            Button("OK", action: session.dismissMediaSelectionError)
        } message: {
            Text(session.mediaSelectionErrorMessage ?? "Plex could not change this playback setting.")
        }
        .alert(
            "Change Video Quality?",
            isPresented: Binding(
                get: { session.qualitySuggestion != nil },
                set: { isPresented in
                    if !isPresented {
                        session.dismissQualitySuggestion()
                    }
                }
            ),
            presenting: session.qualitySuggestion
        ) { suggestion in
            Button("Change to \(suggestion.targetQuality.label)") {
                session.acceptQualitySuggestion()
            }
            Button("Keep Current", role: .cancel) {
                session.dismissQualitySuggestion()
            }
        } message: { suggestion in
            Text(suggestion.message)
        }
        .alert("Couldn’t Update Playback", isPresented: Binding(
            get: { session.queueNavigationErrorMessage != nil },
            set: { if !$0 { session.dismissQueueNavigationError() } }
        )) {
            if session.canRetryQueueOperation {
                Button("Try Again", systemImage: "arrow.clockwise") {
                    session.retryQueueOperation()
                }
            }
            Button("Dismiss", role: .cancel, action: session.dismissQueueNavigationError)
        } message: {
            Text(session.queueNavigationErrorMessage ?? "Plex could not update this playback session.")
        }
        .onDisappear {
            session.stop(store: store, request: request)
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.scenePhaseDidChange(newPhase)
        }
        .onChange(of: store.playbackMarkerPreferences) { _, preferences in
            session.playbackMarkerPreferencesDidChange(preferences, store: store)
        }
    }

    private var videoConversionControl: TVVideoConversionControl? {
        guard session.isVideoPlayback else { return nil }
        if request.forceVideoTranscode {
            return TVVideoConversionControl(isForcingConversion: true)
        }
        guard store.automaticallyAdjustVideoQuality,
              let playbackMethod = session.playbackMethod,
              playbackMethod != .transcode else {
            return nil
        }
        return TVVideoConversionControl(isForcingConversion: false)
    }
}

private struct TVVideoConversionControl: Equatable {
    let isForcingConversion: Bool

    var title: String {
        isForcingConversion ? "Play Original Quality" : "Convert Automatically"
    }

    var systemImage: String {
        isForcingConversion ? "play.rectangle.fill" : "arrow.triangle.2.circlepath"
    }

    var nextValue: Bool { !isForcingConversion }
}

private enum PlexNativeSubtitleStyle {
    static func apply(to playerItem: AVPlayerItem?, size: PlexSubtitleSize) {
        guard let rule = AVTextStyleRule(textMarkupAttributes: [
            kCMTextMarkupAttribute_RelativeFontSize as String: NSNumber(value: size.rawValue),
        ]) else {
            playerItem?.textStyleRules = nil
            return
        }
        playerItem?.textStyleRules = [rule]
    }
}

private struct TVNativePlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    let store: TVAppStore
    let mediaKind: PlexPlaybackMediaKind
    let selectedVideoQuality: PlexVideoQuality
    let selectedMusicQuality: PlexMusicQuality
    let selectedAudioBoost: PlexAudioBoost
    let selectedSubtitleSize: PlexSubtitleSize
    let automaticallySyncsSubtitles: Bool
    let automaticallyAdjustsVideoQuality: Bool
    let videoConversionControl: TVVideoConversionControl?
    let selectedVideoScalingMode: PlexVideoScalingMode
    let showsVideoQualityMenu: Bool
    let showsMusicQualityMenu: Bool
    let showsAudioBoostMenu: Bool
    let showsSubtitleSizeMenu: Bool
    let showsSubtitleAutoSyncAction: Bool
    let subtitleOffsetSelection: PlexSubtitleOffsetSelection?
    let playbackVersionSelection: PlexPlaybackVersionSelection?
    let mediaSelection: PlexServerManagedMediaSelection
    let audioPresentation: PlexAudioPlaybackPresentation?
    let canChangeMediaSelection: Bool
    let playbackInfo: PlexPlaybackInfoPresentation?
    let queuePresentation: PlexPlaybackQueuePresentation?
    let markerAction: PlexPlaybackMarkerAction?
    let availableMarkerKinds: [PlexPlaybackMarkerKind]
    let markerPreferences: PlexPlaybackMarkerPreferences
    let canGoPrevious: Bool
    let canGoNext: Bool
    let previousItemTitle: String?
    let nextItemTitle: String?
    let canChangeShuffle: Bool
    let isShuffled: Bool
    let repeatMode: PlexPlaybackRepeatMode
    let canRepeatAll: Bool
    let sleepTimer: PlexPlaybackSleepTimer
    let selectVideoQuality: (PlexVideoQuality) -> Void
    let selectMusicQuality: (PlexMusicQuality) -> Void
    let selectAudioBoost: (PlexAudioBoost) -> Void
    let selectSubtitleSize: (PlexSubtitleSize) -> Void
    let setSubtitleAutoSync: (Bool) -> Void
    let setSubtitleOffset: (Int) -> Void
    let setVideoConversionForced: (Bool) -> Void
    let selectPlaybackVersion: (Int) -> Void
    let selectVideoScalingMode: (PlexVideoScalingMode) -> Void
    let selectAudioStream: (Int) -> Void
    let selectSubtitleStream: (Int?) -> Void
    let restartFromBeginning: () -> Void
    let playPreviousItem: () -> Void
    let playNextItem: () -> Void
    let playQueuedItem: (String) -> Void
    let moveQueuedItem: (String, PlexPlayQueueItemMoveDirection) -> Void
    let removeQueuedItem: (String) -> Void
    let setShuffled: (Bool) -> Void
    let setRepeatMode: (PlexPlaybackRepeatMode) -> Void
    let setSleepTimer: (PlexPlaybackSleepTimerPreset) -> Void
    let setMarkerBehavior: (PlexPlaybackMarkerBehavior, PlexPlaybackMarkerKind) -> Void
    let skipMarker: () -> Void
    let shouldPresentContentProposal: (AVContentProposal) -> Bool
    let acceptContentProposal: (AVContentProposal) -> Void
    let rejectContentProposal: (AVContentProposal) -> Void
    let shouldHandlePlayPausePress: () -> Bool
    let handlePlayPausePress: () -> Bool
    let recordInteraction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectVideoQuality: selectVideoQuality,
            selectMusicQuality: selectMusicQuality,
            selectAudioBoost: selectAudioBoost,
            selectSubtitleSize: selectSubtitleSize,
            setSubtitleAutoSync: setSubtitleAutoSync,
            setSubtitleOffset: setSubtitleOffset,
            setVideoConversionForced: setVideoConversionForced,
            selectPlaybackVersion: selectPlaybackVersion,
            selectVideoScalingMode: selectVideoScalingMode,
            selectAudioStream: selectAudioStream,
            selectSubtitleStream: selectSubtitleStream,
            restartFromBeginning: restartFromBeginning,
            playPreviousItem: playPreviousItem,
            playNextItem: playNextItem,
            playQueuedItem: playQueuedItem,
            moveQueuedItem: moveQueuedItem,
            removeQueuedItem: removeQueuedItem,
            setShuffled: setShuffled,
            setRepeatMode: setRepeatMode,
            setSleepTimer: setSleepTimer,
            setMarkerBehavior: setMarkerBehavior,
            skipMarker: skipMarker,
            shouldPresentContentProposal: shouldPresentContentProposal,
            acceptContentProposal: acceptContentProposal,
            rejectContentProposal: rejectContentProposal,
            dismissPlayer: store.dismissPlayer,
            recordInteraction: recordInteraction,
            shouldHandlePlayPausePress: shouldHandlePlayPausePress,
            handlePlayPausePress: handlePlayPausePress
        )
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.view.accessibilityIdentifier = "native-player"
        controller.delegate = context.coordinator
        controller.showsPlaybackControls = true
        controller.playbackControlsIncludeTransportBar = true
        controller.playbackControlsIncludeInfoViews = true
        controller.transportBarIncludesTitleView = true
        controller.appliesPreferredDisplayCriteriaAutomatically = true
        controller.allowsPictureInPicturePlayback = audioPresentation == nil
        context.coordinator.installRemotePressRecognizers(in: controller)
        configureSkippingBehavior(controller)
        PlexNativePlaybackSpeedConfiguration.apply(to: controller)
        PlexNativeVideoScalingConfiguration.apply(
            to: controller,
            scalingMode: selectedVideoScalingMode
        )
        PlexNativeSubtitleStyle.apply(to: player.currentItem, size: selectedSubtitleSize)
        configureTransportMenu(controller, coordinator: context.coordinator)
        configureInfoActions(controller, coordinator: context.coordinator)
        context.coordinator.updateContextualAction(markerAction, in: controller)
        context.coordinator.updatePlaybackInfo(playbackInfo, in: controller)
        context.coordinator.updateAudioStage(
            audioPresentation,
            store: store,
            in: controller
        )
        context.coordinator.updatePlaybackQueue(
            queuePresentation,
            store: store,
            canSelectItems: canChangeMediaSelection,
            in: controller
        )
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        let allowsPictureInPicturePlayback = audioPresentation == nil
        if controller.allowsPictureInPicturePlayback != allowsPictureInPicturePlayback {
            controller.allowsPictureInPicturePlayback = allowsPictureInPicturePlayback
        }
        configureSkippingBehavior(controller)
        PlexNativePlaybackSpeedConfiguration.apply(to: controller)
        PlexNativeVideoScalingConfiguration.apply(
            to: controller,
            scalingMode: selectedVideoScalingMode
        )
        PlexNativeSubtitleStyle.apply(to: player.currentItem, size: selectedSubtitleSize)
        context.coordinator.selectVideoQuality = selectVideoQuality
        context.coordinator.selectMusicQuality = selectMusicQuality
        context.coordinator.selectAudioBoost = selectAudioBoost
        context.coordinator.selectSubtitleSize = selectSubtitleSize
        context.coordinator.setSubtitleAutoSync = setSubtitleAutoSync
        context.coordinator.setSubtitleOffset = setSubtitleOffset
        context.coordinator.setVideoConversionForced = setVideoConversionForced
        context.coordinator.selectPlaybackVersion = selectPlaybackVersion
        context.coordinator.selectVideoScalingMode = selectVideoScalingMode
        context.coordinator.selectAudioStream = selectAudioStream
        context.coordinator.selectSubtitleStream = selectSubtitleStream
        context.coordinator.restartFromBeginning = restartFromBeginning
        context.coordinator.playPreviousItem = playPreviousItem
        context.coordinator.playNextItem = playNextItem
        context.coordinator.playQueuedItem = playQueuedItem
        context.coordinator.moveQueuedItem = moveQueuedItem
        context.coordinator.removeQueuedItem = removeQueuedItem
        context.coordinator.setShuffled = setShuffled
        context.coordinator.setRepeatMode = setRepeatMode
        context.coordinator.setSleepTimer = setSleepTimer
        context.coordinator.setMarkerBehavior = setMarkerBehavior
        context.coordinator.skipMarker = skipMarker
        context.coordinator.shouldPresentContentProposal = shouldPresentContentProposal
        context.coordinator.acceptContentProposal = acceptContentProposal
        context.coordinator.rejectContentProposal = rejectContentProposal
        context.coordinator.dismissPlayer = store.dismissPlayer
        context.coordinator.recordInteraction = recordInteraction
        context.coordinator.shouldHandlePlayPausePress = shouldHandlePlayPausePress
        context.coordinator.handlePlayPausePress = handlePlayPausePress
        configureTransportMenu(controller, coordinator: context.coordinator)
        configureInfoActions(controller, coordinator: context.coordinator)
        context.coordinator.updateContextualAction(markerAction, in: controller)
        context.coordinator.updatePlaybackInfo(playbackInfo, in: controller)
        context.coordinator.updateAudioStage(
            audioPresentation,
            store: store,
            in: controller
        )
        context.coordinator.updatePlaybackQueue(
            queuePresentation,
            store: store,
            canSelectItems: canChangeMediaSelection,
            in: controller
        )
    }

    static func dismantleUIViewController(
        _ controller: AVPlayerViewController,
        coordinator: Coordinator
    ) {
        coordinator.dismantle(from: controller)
        controller.player = nil
        controller.delegate = nil
        controller.transportBarCustomMenuItems = []
        controller.infoViewActions = []
        controller.contextualActions = []
        controller.customInfoViewControllers = []
    }

    private func configureSkippingBehavior(_ controller: AVPlayerViewController) {
        let configuration = PlexNativeSkippingConfiguration(
            mediaKind: mediaKind,
            canMovePrevious: canGoPrevious,
            canMoveNext: canGoNext,
            controlsEnabled: canChangeMediaSelection
        )
        let skippingBehavior: AVPlayerViewControllerSkippingBehavior = switch configuration.mode {
        case .time: .default
        case .item: .skipItem
        }
        if controller.skippingBehavior != skippingBehavior {
            controller.skippingBehavior = skippingBehavior
        }

        if controller.isSkipBackwardEnabled != configuration.isBackwardEnabled {
            controller.isSkipBackwardEnabled = configuration.isBackwardEnabled
        }
        if controller.isSkipForwardEnabled != configuration.isForwardEnabled {
            controller.isSkipForwardEnabled = configuration.isForwardEnabled
        }
    }

    private func configureTransportMenu(
        _ controller: AVPlayerViewController,
        coordinator: Coordinator
    ) {
        guard coordinator.shouldUpdateTransportMenu(
            selected: selectedVideoQuality,
            selectedMusicQuality: selectedMusicQuality,
            selectedAudioBoost: selectedAudioBoost,
            selectedSubtitleSize: selectedSubtitleSize,
            automaticallySyncsSubtitles: automaticallySyncsSubtitles,
            automaticallyAdjustsVideoQuality: automaticallyAdjustsVideoQuality,
            videoConversionControl: videoConversionControl,
            scalingMode: selectedVideoScalingMode,
            showsVideoQualityMenu: showsVideoQualityMenu,
            showsMusicQualityMenu: showsMusicQualityMenu,
            showsAudioBoostMenu: showsAudioBoostMenu,
            showsSubtitleSizeMenu: showsSubtitleSizeMenu,
            showsSubtitleAutoSyncAction: showsSubtitleAutoSyncAction,
            subtitleOffsetSelection: subtitleOffsetSelection,
            playbackVersionSelection: playbackVersionSelection,
            mediaSelection: mediaSelection,
            canChangeMediaSelection: canChangeMediaSelection,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext,
            previousItemTitle: previousItemTitle,
            nextItemTitle: nextItemTitle,
            canChangeShuffle: canChangeShuffle,
            isShuffled: isShuffled,
            repeatMode: repeatMode,
            canRepeatAll: canRepeatAll,
            sleepTimer: sleepTimer,
            availableMarkerKinds: availableMarkerKinds,
            markerPreferences: markerPreferences
        ) else {
            return
        }
        var playbackItems: [UIMenuElement] = []
        if let playbackVersionSelection {
            playbackItems.append(coordinator.playbackVersionMenu(
                selection: playbackVersionSelection,
                canChange: canChangeMediaSelection
            ))
        }
        if showsVideoQualityMenu {
            playbackItems.append(coordinator.qualityMenu(
                selected: selectedVideoQuality,
                automaticallyAdjusts: automaticallyAdjustsVideoQuality,
                canChange: canChangeMediaSelection
            ))
            if let videoConversionControl {
                playbackItems.append(coordinator.videoConversionAction(
                    control: videoConversionControl,
                    canChange: canChangeMediaSelection
                ))
            }
            playbackItems.append(
                coordinator.videoScalingMenu(selected: selectedVideoScalingMode)
            )
        }
        if showsMusicQualityMenu {
            playbackItems.append(coordinator.musicQualityMenu(
                selected: selectedMusicQuality,
                canChange: canChangeMediaSelection
            ))
        }

        var audioAndSubtitleItems: [UIMenuElement] = []
        if !mediaSelection.audioOptions.isEmpty {
            audioAndSubtitleItems.append(coordinator.audioMenu(
                options: mediaSelection.audioOptions,
                canChange: canChangeMediaSelection
            ))
        }
        if !mediaSelection.subtitleOptions.isEmpty {
            audioAndSubtitleItems.append(coordinator.subtitleMenu(
                options: mediaSelection.subtitleOptions,
                canChange: canChangeMediaSelection
            ))
        }
        if showsAudioBoostMenu {
            audioAndSubtitleItems.append(coordinator.audioBoostMenu(
                selected: selectedAudioBoost,
                canChange: canChangeMediaSelection
            ))
        }
        if showsSubtitleSizeMenu {
            audioAndSubtitleItems.append(coordinator.subtitleSizeMenu(
                selected: selectedSubtitleSize,
                canChange: canChangeMediaSelection
            ))
        }
        if showsSubtitleAutoSyncAction {
            audioAndSubtitleItems.append(coordinator.subtitleAutoSyncAction(
                isEnabled: automaticallySyncsSubtitles,
                canChange: canChangeMediaSelection
            ))
        }
        if let subtitleOffsetSelection {
            audioAndSubtitleItems.append(coordinator.subtitleOffsetMenu(
                selection: subtitleOffsetSelection,
                canChange: canChangeMediaSelection
            ))
        }
        if !audioAndSubtitleItems.isEmpty {
            playbackItems.append(coordinator.transportGroupMenu(
                title: "Audio & Subtitles",
                systemImage: "captions.bubble.fill",
                children: audioAndSubtitleItems
            ))
        }

        var queueAndTimingItems: [UIMenuElement] = []
        if canGoPrevious || canGoNext || canChangeShuffle {
            queueAndTimingItems.append(coordinator.queueMenu(
                canGoPrevious: canGoPrevious && canChangeMediaSelection,
                canGoNext: canGoNext && canChangeMediaSelection,
                previousItemTitle: previousItemTitle,
                nextItemTitle: nextItemTitle,
                canChangeShuffle: canChangeShuffle && canChangeMediaSelection,
                isShuffled: isShuffled
            ))
        }
        queueAndTimingItems.append(coordinator.repeatMenu(
            selected: repeatMode,
            canRepeatAll: canRepeatAll,
            canChange: canChangeMediaSelection
        ))
        if !availableMarkerKinds.isEmpty {
            queueAndTimingItems.append(contentsOf: coordinator.markerBehaviorMenus(
                kinds: availableMarkerKinds,
                preferences: markerPreferences
            ))
        }
        queueAndTimingItems.append(coordinator.sleepTimerMenu(
            selected: sleepTimer.preset,
            canChange: canChangeMediaSelection
        ))

        var items: [UIMenuElement] = []
        if !playbackItems.isEmpty {
            items.append(coordinator.transportGroupMenu(
                title: "Playback",
                systemImage: "slider.horizontal.3",
                children: playbackItems
            ))
        }
        items.append(coordinator.transportGroupMenu(
            title: "Queue & Timing",
            systemImage: "text.line.first.and.arrowtriangle.forward",
            children: queueAndTimingItems
        ))
        controller.transportBarCustomMenuItems = items
    }

    private func configureInfoActions(
        _ controller: AVPlayerViewController,
        coordinator: Coordinator
    ) {
        guard coordinator.shouldUpdateInfoActions(
            hasNextItem: canGoNext,
            nextItemTitle: nextItemTitle,
            controlsEnabled: canChangeMediaSelection
        ) else {
            return
        }
        controller.infoViewActions = coordinator.infoActions(
            hasNextItem: canGoNext,
            nextItemTitle: nextItemTitle,
            controlsEnabled: canChangeMediaSelection
        )
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate, UIGestureRecognizerDelegate {
        var selectVideoQuality: (PlexVideoQuality) -> Void
        var selectMusicQuality: (PlexMusicQuality) -> Void
        var selectAudioBoost: (PlexAudioBoost) -> Void
        var selectSubtitleSize: (PlexSubtitleSize) -> Void
        var setSubtitleAutoSync: (Bool) -> Void
        var setSubtitleOffset: (Int) -> Void
        var setVideoConversionForced: (Bool) -> Void
        var selectPlaybackVersion: (Int) -> Void
        var selectVideoScalingMode: (PlexVideoScalingMode) -> Void
        var selectAudioStream: (Int) -> Void
        var selectSubtitleStream: (Int?) -> Void
        var restartFromBeginning: () -> Void
        var playPreviousItem: () -> Void
        var playNextItem: () -> Void
        var playQueuedItem: (String) -> Void
        var moveQueuedItem: (String, PlexPlayQueueItemMoveDirection) -> Void
        var removeQueuedItem: (String) -> Void
        var setShuffled: (Bool) -> Void
        var setRepeatMode: (PlexPlaybackRepeatMode) -> Void
        var setSleepTimer: (PlexPlaybackSleepTimerPreset) -> Void
        var setMarkerBehavior: (PlexPlaybackMarkerBehavior, PlexPlaybackMarkerKind) -> Void
        var skipMarker: () -> Void
        var shouldPresentContentProposal: (AVContentProposal) -> Bool
        var acceptContentProposal: (AVContentProposal) -> Void
        var rejectContentProposal: (AVContentProposal) -> Void
        var dismissPlayer: () -> Void
        var recordInteraction: () -> Void
        var shouldHandlePlayPausePress: () -> Bool
        var handlePlayPausePress: () -> Bool
        private var transportMenuConfiguration: TransportMenuConfiguration?
        private var infoActionConfiguration: InfoActionConfiguration?
        private var playbackInfo: PlexPlaybackInfoPresentation?
        private var playbackInfoController: UIHostingController<TVPlaybackInfoView>?
        private var queuePresentation: PlexPlaybackQueuePresentation?
        private var canSelectQueueItems = false
        private var playbackQueueController: UIHostingController<TVPlaybackQueueHostView>?
        private var markerAction: PlexPlaybackMarkerAction?
        private let audioStageHost = TVAudioPlayerStageHost()
        private weak var playPauseRecognizer: UITapGestureRecognizer?
        private weak var interactionRecognizer: UITapGestureRecognizer?

        init(
            selectVideoQuality: @escaping (PlexVideoQuality) -> Void,
            selectMusicQuality: @escaping (PlexMusicQuality) -> Void,
            selectAudioBoost: @escaping (PlexAudioBoost) -> Void,
            selectSubtitleSize: @escaping (PlexSubtitleSize) -> Void,
            setSubtitleAutoSync: @escaping (Bool) -> Void,
            setSubtitleOffset: @escaping (Int) -> Void,
            setVideoConversionForced: @escaping (Bool) -> Void,
            selectPlaybackVersion: @escaping (Int) -> Void,
            selectVideoScalingMode: @escaping (PlexVideoScalingMode) -> Void,
            selectAudioStream: @escaping (Int) -> Void,
            selectSubtitleStream: @escaping (Int?) -> Void,
            restartFromBeginning: @escaping () -> Void,
            playPreviousItem: @escaping () -> Void,
            playNextItem: @escaping () -> Void,
            playQueuedItem: @escaping (String) -> Void,
            moveQueuedItem: @escaping (String, PlexPlayQueueItemMoveDirection) -> Void,
            removeQueuedItem: @escaping (String) -> Void,
            setShuffled: @escaping (Bool) -> Void,
            setRepeatMode: @escaping (PlexPlaybackRepeatMode) -> Void,
            setSleepTimer: @escaping (PlexPlaybackSleepTimerPreset) -> Void,
            setMarkerBehavior: @escaping (
                PlexPlaybackMarkerBehavior,
                PlexPlaybackMarkerKind
            ) -> Void,
            skipMarker: @escaping () -> Void,
            shouldPresentContentProposal: @escaping (AVContentProposal) -> Bool,
            acceptContentProposal: @escaping (AVContentProposal) -> Void,
            rejectContentProposal: @escaping (AVContentProposal) -> Void,
            dismissPlayer: @escaping () -> Void,
            recordInteraction: @escaping () -> Void,
            shouldHandlePlayPausePress: @escaping () -> Bool,
            handlePlayPausePress: @escaping () -> Bool
        ) {
            self.selectVideoQuality = selectVideoQuality
            self.selectMusicQuality = selectMusicQuality
            self.selectAudioBoost = selectAudioBoost
            self.selectSubtitleSize = selectSubtitleSize
            self.setSubtitleAutoSync = setSubtitleAutoSync
            self.setSubtitleOffset = setSubtitleOffset
            self.setVideoConversionForced = setVideoConversionForced
            self.selectPlaybackVersion = selectPlaybackVersion
            self.selectVideoScalingMode = selectVideoScalingMode
            self.selectAudioStream = selectAudioStream
            self.selectSubtitleStream = selectSubtitleStream
            self.restartFromBeginning = restartFromBeginning
            self.playPreviousItem = playPreviousItem
            self.playNextItem = playNextItem
            self.playQueuedItem = playQueuedItem
            self.moveQueuedItem = moveQueuedItem
            self.removeQueuedItem = removeQueuedItem
            self.setShuffled = setShuffled
            self.setRepeatMode = setRepeatMode
            self.setSleepTimer = setSleepTimer
            self.setMarkerBehavior = setMarkerBehavior
            self.skipMarker = skipMarker
            self.shouldPresentContentProposal = shouldPresentContentProposal
            self.acceptContentProposal = acceptContentProposal
            self.rejectContentProposal = rejectContentProposal
            self.dismissPlayer = dismissPlayer
            self.recordInteraction = recordInteraction
            self.shouldHandlePlayPausePress = shouldHandlePlayPausePress
            self.handlePlayPausePress = handlePlayPausePress
            super.init()
        }

        func installRemotePressRecognizers(in playerViewController: AVPlayerViewController) {
            if playPauseRecognizer?.view === playerViewController.view {
                return
            }
            if let playPauseRecognizer {
                playPauseRecognizer.view?.removeGestureRecognizer(playPauseRecognizer)
            }

            let recognizer = UITapGestureRecognizer(
                target: self,
                action: #selector(handlePlayPausePress(_:))
            )
            recognizer.allowedPressTypes = [
                NSNumber(value: UIPress.PressType.playPause.rawValue)
            ]
            recognizer.delegate = self
            playerViewController.view.addGestureRecognizer(recognizer)
            playPauseRecognizer = recognizer

            let interactionRecognizer = UITapGestureRecognizer(
                target: self,
                action: #selector(recordRemoteInteraction(_:))
            )
            interactionRecognizer.allowedPressTypes = [
                UIPress.PressType.select,
                .menu,
                .playPause,
                .upArrow,
                .downArrow,
                .leftArrow,
                .rightArrow,
                .pageUp,
                .pageDown,
            ].map { NSNumber(value: $0.rawValue) }
            interactionRecognizer.cancelsTouchesInView = false
            interactionRecognizer.delegate = self
            playerViewController.view.addGestureRecognizer(interactionRecognizer)
            self.interactionRecognizer = interactionRecognizer
        }

        func dismantle(from playerViewController: AVPlayerViewController) {
            if let playPauseRecognizer {
                playPauseRecognizer.view?.removeGestureRecognizer(playPauseRecognizer)
                self.playPauseRecognizer = nil
            }
            if let interactionRecognizer {
                interactionRecognizer.view?.removeGestureRecognizer(interactionRecognizer)
                self.interactionRecognizer = nil
            }
            audioStageHost.remove()
            playbackInfoController = nil
            playbackQueueController = nil
            playerViewController.customInfoViewControllers = []
        }

        @objc private func handlePlayPausePress(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            recordInteraction()
            _ = handlePlayPausePress()
        }

        @objc private func recordRemoteInteraction(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            recordInteraction()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === interactionRecognizer
                || otherGestureRecognizer === interactionRecognizer
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === playPauseRecognizer else { return true }
            return shouldHandlePlayPausePress()
        }

        func updateContextualAction(
            _ action: PlexPlaybackMarkerAction?,
            in playerViewController: AVPlayerViewController
        ) {
            guard action != markerAction else { return }
            markerAction = action

            guard let action else {
                playerViewController.contextualActions = []
                return
            }
            playerViewController.contextualActions = [
                UIAction(
                    title: action.label,
                    image: UIImage(systemName: "forward.end.fill"),
                    discoverabilityTitle: action.accessibilityHint
                ) { [weak self] _ in
                    self?.skipMarker()
                },
            ]
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            shouldPresent proposal: AVContentProposal
        ) -> Bool {
            shouldPresentContentProposal(proposal)
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            didAccept proposal: AVContentProposal
        ) {
            acceptContentProposal(proposal)
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            didReject proposal: AVContentProposal
        ) {
            rejectContentProposal(proposal)
        }

        func playerViewControllerShouldDismiss(
            _ playerViewController: AVPlayerViewController
        ) -> Bool {
            dismissPlayer()
            return false
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willResumePlaybackAfterUserNavigatedFrom oldTime: CMTime,
            to targetTime: CMTime
        ) {
            recordInteraction()
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            didSelect mediaSelectionOption: AVMediaSelectionOption?,
            in mediaSelectionGroup: AVMediaSelectionGroup
        ) {
            recordInteraction()
        }

        func skipToNextItem(for playerViewController: AVPlayerViewController) {
            playNextItem()
        }

        func skipToPreviousItem(for playerViewController: AVPlayerViewController) {
            playPreviousItem()
        }

        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(
            _ playerViewController: AVPlayerViewController
        ) -> Bool {
            false
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }

        func updatePlaybackInfo(
            _ presentation: PlexPlaybackInfoPresentation?,
            in playerViewController: AVPlayerViewController
        ) {
            guard presentation != playbackInfo else { return }
            playbackInfo = presentation

            guard let presentation else {
                playbackInfoController = nil
                publishInfoControllers(in: playerViewController)
                return
            }

            if let playbackInfoController {
                playbackInfoController.rootView = TVPlaybackInfoView(presentation: presentation)
                publishInfoControllers(in: playerViewController)
                return
            }

            let infoController = UIHostingController(
                rootView: TVPlaybackInfoView(presentation: presentation)
            )
            infoController.title = "Playback Info"
            infoController.preferredContentSize = CGSize(width: 1_600, height: 600)
            infoController.view.backgroundColor = .clear
            playbackInfoController = infoController
            publishInfoControllers(in: playerViewController)
        }

        func updateAudioStage(
            _ presentation: PlexAudioPlaybackPresentation?,
            store: TVAppStore,
            in playerViewController: AVPlayerViewController
        ) {
            audioStageHost.update(
                in: playerViewController.contentOverlayView,
                store: store,
                presentation: presentation
            )
        }

        func updatePlaybackQueue(
            _ presentation: PlexPlaybackQueuePresentation?,
            store: TVAppStore,
            canSelectItems: Bool,
            in playerViewController: AVPlayerViewController
        ) {
            guard presentation != queuePresentation
                    || canSelectItems != canSelectQueueItems else {
                return
            }
            queuePresentation = presentation
            canSelectQueueItems = canSelectItems

            guard let presentation, !presentation.upcomingItems.isEmpty else {
                playbackQueueController = nil
                publishInfoControllers(in: playerViewController)
                return
            }

            let rootView = TVPlaybackQueueHostView(
                store: store,
                presentation: presentation,
                canSelectItems: canSelectItems
            ) { [weak self] playQueueItemID in
                self?.playQueuedItem(playQueueItemID)
            } move: { [weak self] playQueueItemID, direction in
                self?.moveQueuedItem(playQueueItemID, direction)
            } remove: { [weak self] playQueueItemID in
                self?.removeQueuedItem(playQueueItemID)
            }
            if let playbackQueueController {
                playbackQueueController.rootView = rootView
                publishInfoControllers(in: playerViewController)
                return
            }

            let queueController = UIHostingController(rootView: rootView)
            queueController.title = "Up Next"
            queueController.preferredContentSize = CGSize(width: 1_600, height: 600)
            queueController.view.backgroundColor = .clear
            playbackQueueController = queueController
            publishInfoControllers(in: playerViewController)
        }

        private func publishInfoControllers(in playerViewController: AVPlayerViewController) {
            playerViewController.customInfoViewControllers = [
                playbackQueueController,
                playbackInfoController,
            ].compactMap { $0 }
        }

        func shouldUpdateTransportMenu(
            selected: PlexVideoQuality,
            selectedMusicQuality: PlexMusicQuality,
            selectedAudioBoost: PlexAudioBoost,
            selectedSubtitleSize: PlexSubtitleSize,
            automaticallySyncsSubtitles: Bool,
            automaticallyAdjustsVideoQuality: Bool,
            videoConversionControl: TVVideoConversionControl?,
            scalingMode: PlexVideoScalingMode,
            showsVideoQualityMenu: Bool,
            showsMusicQualityMenu: Bool,
            showsAudioBoostMenu: Bool,
            showsSubtitleSizeMenu: Bool,
            showsSubtitleAutoSyncAction: Bool,
            subtitleOffsetSelection: PlexSubtitleOffsetSelection?,
            playbackVersionSelection: PlexPlaybackVersionSelection?,
            mediaSelection: PlexServerManagedMediaSelection,
            canChangeMediaSelection: Bool,
            canGoPrevious: Bool,
            canGoNext: Bool,
            previousItemTitle: String?,
            nextItemTitle: String?,
            canChangeShuffle: Bool,
            isShuffled: Bool,
            repeatMode: PlexPlaybackRepeatMode,
            canRepeatAll: Bool,
            sleepTimer: PlexPlaybackSleepTimer,
            availableMarkerKinds: [PlexPlaybackMarkerKind],
            markerPreferences: PlexPlaybackMarkerPreferences
        ) -> Bool {
            let configuration = TransportMenuConfiguration(
                selectedVideoQuality: selected,
                selectedMusicQuality: selectedMusicQuality,
                selectedAudioBoost: selectedAudioBoost,
                selectedSubtitleSize: selectedSubtitleSize,
                automaticallySyncsSubtitles: automaticallySyncsSubtitles,
                automaticallyAdjustsVideoQuality: automaticallyAdjustsVideoQuality,
                videoConversionControl: videoConversionControl,
                selectedVideoScalingMode: scalingMode,
                showsVideoQualityMenu: showsVideoQualityMenu,
                showsMusicQualityMenu: showsMusicQualityMenu,
                showsAudioBoostMenu: showsAudioBoostMenu,
                showsSubtitleSizeMenu: showsSubtitleSizeMenu,
                showsSubtitleAutoSyncAction: showsSubtitleAutoSyncAction,
                subtitleOffsetSelection: subtitleOffsetSelection,
                playbackVersionSelection: playbackVersionSelection,
                mediaSelection: mediaSelection,
                canChangeMediaSelection: canChangeMediaSelection,
                canGoPrevious: canGoPrevious,
                canGoNext: canGoNext,
                previousItemTitle: previousItemTitle,
                nextItemTitle: nextItemTitle,
                canChangeShuffle: canChangeShuffle,
                isShuffled: isShuffled,
                repeatMode: repeatMode,
                canRepeatAll: canRepeatAll,
                sleepTimer: sleepTimer,
                availableMarkerKinds: availableMarkerKinds,
                markerPreferences: markerPreferences
            )
            guard configuration != transportMenuConfiguration else { return false }
            transportMenuConfiguration = configuration
            return true
        }

        func playbackVersionMenu(
            selection: PlexPlaybackVersionSelection,
            canChange: Bool
        ) -> UIMenu {
            let actions = selection.options.map { option in
                UIAction(
                    title: option.label,
                    attributes: canChange ? [] : .disabled,
                    state: option.id == selection.selectedID ? .on : .off
                ) { [weak self] _ in
                    self?.selectPlaybackVersion(option.id)
                }
            }
            return UIMenu(
                title: "Version",
                image: UIImage(systemName: "rectangle.stack.fill"),
                options: .singleSelection,
                children: actions
            )
        }

        func qualityMenu(
            selected: PlexVideoQuality,
            automaticallyAdjusts: Bool,
            canChange: Bool
        ) -> UIMenu {
            let actions = PlexVideoQuality.allCases.map { quality in
                UIAction(
                    title: quality.label,
                    attributes: canChange ? [] : .disabled,
                    state: quality == selected ? .on : .off
                ) { [weak self] _ in
                    self?.selectVideoQuality(quality)
                }
            }
            return UIMenu(
                title: automaticallyAdjusts ? "Starting Quality" : "Quality",
                image: UIImage(systemName: "4k.tv"),
                options: .singleSelection,
                children: actions
            )
        }

        func musicQualityMenu(
            selected: PlexMusicQuality,
            canChange: Bool
        ) -> UIMenu {
            let actions = PlexMusicQuality.allCases.map { quality in
                UIAction(
                    title: quality.label,
                    attributes: canChange ? [] : .disabled,
                    state: quality == selected ? .on : .off
                ) { [weak self] _ in
                    self?.selectMusicQuality(quality)
                }
            }
            return UIMenu(
                title: "Music Quality",
                image: UIImage(systemName: "waveform"),
                options: .singleSelection,
                children: actions
            )
        }

        func audioBoostMenu(
            selected: PlexAudioBoost,
            canChange: Bool
        ) -> UIMenu {
            let actions = PlexAudioBoost.allCases.map { boost in
                UIAction(
                    title: boost.label,
                    subtitle: boost.percentageLabel,
                    attributes: canChange ? [] : .disabled,
                    state: boost == selected ? .on : .off
                ) { [weak self] _ in
                    self?.selectAudioBoost(boost)
                }
            }
            return UIMenu(
                title: "Audio Boost",
                subtitle: "Transcoded surround to stereo",
                image: UIImage(systemName: "speaker.wave.3.fill"),
                options: .singleSelection,
                children: actions
            )
        }

        func subtitleSizeMenu(
            selected: PlexSubtitleSize,
            canChange: Bool
        ) -> UIMenu {
            let actions = PlexSubtitleSize.allCases.map { size in
                UIAction(
                    title: size.label,
                    subtitle: size.percentageLabel,
                    attributes: canChange ? [] : .disabled,
                    state: size == selected ? .on : .off
                ) { [weak self] _ in
                    self?.selectSubtitleSize(size)
                }
            }
            return UIMenu(
                title: "Subtitle Size",
                image: UIImage(systemName: "textformat.size"),
                options: .singleSelection,
                children: actions
            )
        }

        func subtitleAutoSyncAction(
            isEnabled: Bool,
            canChange: Bool
        ) -> UIAction {
            UIAction(
                title: "Auto-Sync Subtitles",
                subtitle: "Align timing to detected dialogue",
                image: UIImage(systemName: "captions.bubble.fill"),
                attributes: canChange ? [] : .disabled,
                state: isEnabled ? .on : .off
            ) { [weak self] _ in
                self?.setSubtitleAutoSync(!isEnabled)
            }
        }

        func subtitleOffsetMenu(
            selection: PlexSubtitleOffsetSelection,
            canChange: Bool
        ) -> UIMenu {
            let step = PlexSubtitleOffsetSelection.adjustmentStepMilliseconds
            let attributes: UIMenuElement.Attributes = canChange ? [] : .disabled
            let decrease = UIAction(
                title: "Decrease by \(step) ms",
                image: UIImage(systemName: "minus"),
                attributes: attributes
            ) { [weak self] _ in
                guard let target = selection.adjusted(by: -step) else { return }
                self?.setSubtitleOffset(target)
            }
            let increase = UIAction(
                title: "Increase by \(step) ms",
                image: UIImage(systemName: "plus"),
                attributes: attributes
            ) { [weak self] _ in
                guard let target = selection.adjusted(by: step) else { return }
                self?.setSubtitleOffset(target)
            }
            let reset = UIAction(
                title: "Reset to 0 ms",
                image: UIImage(systemName: "arrow.counterclockwise"),
                attributes: canChange && selection.milliseconds != 0 ? [] : .disabled
            ) { [weak self] _ in
                self?.setSubtitleOffset(0)
            }
            return UIMenu(
                title: "Subtitle Offset",
                subtitle: selection.displayValue,
                image: UIImage(systemName: "captions.bubble.fill"),
                children: [decrease, increase, reset]
            )
        }

        func videoScalingMenu(selected: PlexVideoScalingMode) -> UIMenu {
            let actions = PlexVideoScalingMode.allCases.map { scalingMode in
                UIAction(
                    title: scalingMode.label,
                    state: scalingMode == selected ? .on : .off
                ) { [weak self] _ in
                    self?.selectVideoScalingMode(scalingMode)
                }
            }
            return UIMenu(
                title: "Video Scaling",
                image: UIImage(systemName: "arrow.up.left.and.arrow.down.right"),
                options: .singleSelection,
                children: actions
            )
        }

        func videoConversionAction(
            control: TVVideoConversionControl,
            canChange: Bool
        ) -> UIAction {
            UIAction(
                title: control.title,
                image: UIImage(systemName: control.systemImage),
                attributes: canChange ? [] : .disabled
            ) { [weak self] _ in
                self?.setVideoConversionForced(control.nextValue)
            }
        }

        func startOverAction(canChange: Bool) -> UIAction {
            UIAction(
                title: "Start Over",
                image: UIImage(systemName: "backward.end.fill"),
                attributes: canChange ? [] : .disabled
            ) { [weak self] _ in
                self?.restartFromBeginning()
            }
        }

        func transportGroupMenu(
            title: String,
            systemImage: String,
            children: [UIMenuElement]
        ) -> UIMenu {
            UIMenu(
                title: title,
                image: UIImage(systemName: systemImage),
                children: children
            )
        }

        func shouldUpdateInfoActions(
            hasNextItem: Bool,
            nextItemTitle: String?,
            controlsEnabled: Bool
        ) -> Bool {
            let configuration = InfoActionConfiguration(
                hasNextItem: hasNextItem,
                nextItemTitle: nextItemTitle,
                controlsEnabled: controlsEnabled
            )
            guard configuration != infoActionConfiguration else { return false }
            infoActionConfiguration = configuration
            return true
        }

        func infoActions(
            hasNextItem: Bool,
            nextItemTitle: String?,
            controlsEnabled: Bool
        ) -> [UIAction] {
            var actions = [startOverAction(canChange: controlsEnabled)]
            if hasNextItem {
                actions.append(UIAction(
                    title: "Play Next",
                    subtitle: nextItemTitle,
                    image: UIImage(systemName: "forward.end.fill"),
                    attributes: controlsEnabled ? [] : .disabled
                ) { [weak self] _ in
                    self?.playNextItem()
                })
            }
            return actions
        }

        func queueMenu(
            canGoPrevious: Bool,
            canGoNext: Bool,
            previousItemTitle: String?,
            nextItemTitle: String?,
            canChangeShuffle: Bool,
            isShuffled: Bool
        ) -> UIMenu {
            let previous = UIAction(
                title: "Previous",
                subtitle: previousItemTitle,
                image: UIImage(systemName: "backward.end.fill"),
                attributes: canGoPrevious ? [] : .disabled
            ) { [weak self] _ in
                self?.playPreviousItem()
            }
            let next = UIAction(
                title: "Next",
                subtitle: nextItemTitle,
                image: UIImage(systemName: "forward.end.fill"),
                attributes: canGoNext ? [] : .disabled
            ) { [weak self] _ in
                self?.playNextItem()
            }
            let shuffle = UIAction(
                title: "Shuffle",
                image: UIImage(systemName: "shuffle"),
                attributes: canChangeShuffle ? [] : .disabled,
                state: isShuffled ? .on : .off
            ) { [weak self] _ in
                self?.setShuffled(!isShuffled)
            }
            return UIMenu(
                title: "Queue",
                image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward"),
                children: [
                    previous,
                    next,
                    shuffle,
                ]
            )
        }

        func repeatMenu(
            selected: PlexPlaybackRepeatMode,
            canRepeatAll: Bool,
            canChange: Bool
        ) -> UIMenu {
            let actions = PlexPlaybackRepeatMode.allCases.map { repeatMode in
                let isAvailable = canChange && (repeatMode != .all || canRepeatAll)
                return UIAction(
                    title: repeatMode.label,
                    attributes: isAvailable ? [] : .disabled,
                    state: repeatMode == selected ? .on : .off
                ) { [weak self] _ in
                    self?.setRepeatMode(repeatMode)
                }
            }
            return UIMenu(
                title: "Repeat",
                image: UIImage(systemName: selected == .one ? "repeat.1" : "repeat"),
                options: .singleSelection,
                children: actions
            )
        }

        func sleepTimerMenu(
            selected: PlexPlaybackSleepTimerPreset,
            canChange: Bool
        ) -> UIMenu {
            let actions = PlexPlaybackSleepTimerPreset.allCases.map { preset in
                UIAction(
                    title: preset.label,
                    attributes: canChange ? [] : .disabled,
                    state: preset == selected ? .on : .off
                ) { [weak self] _ in
                    self?.setSleepTimer(preset)
                }
            }
            return UIMenu(
                title: "Sleep Timer",
                image: UIImage(systemName: "moon.zzz.fill"),
                options: .singleSelection,
                children: actions
            )
        }

        func markerBehaviorMenus(
            kinds: [PlexPlaybackMarkerKind],
            preferences: PlexPlaybackMarkerPreferences
        ) -> [UIMenu] {
            kinds.map { kind in
                let actions = PlexPlaybackMarkerBehavior.allCases.map { behavior in
                    UIAction(
                        title: behavior.label,
                        state: preferences.behavior(for: kind) == behavior ? .on : .off
                    ) { [weak self] _ in
                        self?.setMarkerBehavior(behavior, kind)
                    }
                }
                return UIMenu(
                    title: "Skip \(kind.settingsLabel)",
                    image: markerMenuImage(for: kind),
                    options: .singleSelection,
                    children: actions
                )
            }
        }

        private func markerMenuImage(for kind: PlexPlaybackMarkerKind) -> UIImage? {
            switch kind {
            case .intro:
                UIImage(systemName: "forward.end.circle.fill")
            case .commercial:
                UIImage(systemName: "megaphone.fill")
            case .credits:
                UIImage(systemName: "checkered.flag")
            }
        }

        func audioMenu(
            options: [PlexMediaSelectionOption],
            canChange: Bool
        ) -> UIMenu {
            let actions = options.map { option in
                UIAction(
                    title: option.title,
                    attributes: canChange ? [] : .disabled,
                    state: option.isSelected ? .on : .off
                ) { [weak self] _ in
                    self?.selectAudioStream(option.id)
                }
            }
            return UIMenu(
                title: "Audio Track",
                image: UIImage(systemName: "speaker.wave.2.fill"),
                options: .singleSelection,
                children: actions
            )
        }

        func subtitleMenu(
            options: [PlexMediaSelectionOption],
            canChange: Bool
        ) -> UIMenu {
            let attributes: UIMenuElement.Attributes = canChange ? [] : .disabled
            let selectedStreamID = options.first(where: \.isSelected)?.id
            let off = UIAction(
                title: "Off",
                attributes: attributes,
                state: selectedStreamID == nil ? .on : .off
            ) { [weak self] _ in
                self?.selectSubtitleStream(nil)
            }
            let actions = options.map { option in
                UIAction(
                    title: option.title,
                    attributes: attributes,
                    state: option.isSelected ? .on : .off
                ) { [weak self] _ in
                    self?.selectSubtitleStream(option.id)
                }
            }
            return UIMenu(
                title: "Subtitles",
                image: UIImage(systemName: "captions.bubble.fill"),
                options: .singleSelection,
                children: [off] + actions
            )
        }

        private struct TransportMenuConfiguration: Equatable {
            let selectedVideoQuality: PlexVideoQuality
            let selectedMusicQuality: PlexMusicQuality
            let selectedAudioBoost: PlexAudioBoost
            let selectedSubtitleSize: PlexSubtitleSize
            let automaticallySyncsSubtitles: Bool
            let automaticallyAdjustsVideoQuality: Bool
            let videoConversionControl: TVVideoConversionControl?
            let selectedVideoScalingMode: PlexVideoScalingMode
            let showsVideoQualityMenu: Bool
            let showsMusicQualityMenu: Bool
            let showsAudioBoostMenu: Bool
            let showsSubtitleSizeMenu: Bool
            let showsSubtitleAutoSyncAction: Bool
            let subtitleOffsetSelection: PlexSubtitleOffsetSelection?
            let playbackVersionSelection: PlexPlaybackVersionSelection?
            let mediaSelection: PlexServerManagedMediaSelection
            let canChangeMediaSelection: Bool
            let canGoPrevious: Bool
            let canGoNext: Bool
            let previousItemTitle: String?
            let nextItemTitle: String?
            let canChangeShuffle: Bool
            let isShuffled: Bool
            let repeatMode: PlexPlaybackRepeatMode
            let canRepeatAll: Bool
            let sleepTimer: PlexPlaybackSleepTimer
            let availableMarkerKinds: [PlexPlaybackMarkerKind]
            let markerPreferences: PlexPlaybackMarkerPreferences
        }

        private struct InfoActionConfiguration: Equatable {
            let hasNextItem: Bool
            let nextItemTitle: String?
            let controlsEnabled: Bool
        }
    }
}

@MainActor
@Observable
final class TVPlaybackSession {
    @ObservationIgnored private let makePlayerItem: (URL) -> AVPlayerItem

    init(makePlayerItem: @escaping (URL) -> AVPlayerItem = { AVPlayerItem(url: $0) }) {
        self.makePlayerItem = makePlayerItem
    }

    private(set) var player: AVPlayer?
    private(set) var errorMessage: String?
    private(set) var playbackMediaKind: PlexPlaybackMediaKind = .video
    private(set) var playbackMethod: PlexPlaybackPlan.Method?
    private(set) var selectedVideoQuality: PlexVideoQuality?
    private(set) var selectedMusicQuality: PlexMusicQuality?
    private(set) var selectedAudioBoost: PlexAudioBoost?
    private(set) var supportsAudioBoost = false
    private(set) var supportsSubtitleAutoSync = false
    private(set) var subtitleOffsetSelection: PlexSubtitleOffsetSelection?
    var hasAvailableSubtitles: Bool {
        mediaSelection?.subtitleOptions.isEmpty == false
    }
    var hasSelectedSubtitle: Bool {
        mediaSelection?.hasSelectedSubtitle == true
    }
    var isVideoPlayback: Bool { playbackMediaKind == .video }
    var isMusicPlayback: Bool { playbackMediaKind == .music }
    private(set) var audioPresentation: PlexAudioPlaybackPresentation?
    private(set) var playbackVersionSelection: PlexPlaybackVersionSelection?
    private(set) var activeMarkerAction: PlexPlaybackMarkerAction?
    private(set) var availableMarkerKinds: [PlexPlaybackMarkerKind] = []
    private(set) var upNextItem: PlexMediaItem?
    private(set) var postPlayTitle = "Up Next"
    private(set) var postPlayCountdown: Int?
    private(set) var serverManagedMediaSelection = PlexServerManagedMediaSelection()
    private(set) var isReconfiguringMediaSelection = false
    private(set) var mediaSelectionErrorMessage: String?
    private(set) var canRetryPlayback = true
    private(set) var playbackInfo: PlexPlaybackInfoPresentation?
    private(set) var queuePresentation: PlexPlaybackQueuePresentation?
    private(set) var canGoPrevious = false
    private(set) var canGoNext = false
    private(set) var previousItemTitle: String?
    private(set) var nextItemTitle: String?
    private(set) var isNavigatingQueue = false
    private(set) var isMutatingQueue = false
    private(set) var isReplacingPlayback = false
    private(set) var canChangeShuffle = false
    private(set) var isShuffled = false
    private(set) var repeatMode: PlexPlaybackRepeatMode = .off
    private(set) var canRepeatAll = false
    private(set) var queueNavigationErrorMessage: String?
    private(set) var qualitySuggestion: PlexPlaybackQualitySuggestion?
    var canRetryQueueOperation: Bool { failedQueueOperation != nil }
    var isPreparingInitialPosition: Bool { pendingInitialSeekPosition != nil }
    private var pendingInitialSeekPosition: TimeInterval?

    @ObservationIgnored private var positionObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failedToEndObserver: NSObjectProtocol?
    @ObservationIgnored private var timeJumpObserver: NSObjectProtocol?
    @ObservationIgnored private var playbackStalledObserver: NSObjectProtocol?
    @ObservationIgnored private var audioInterruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var mediaServicesResetObserver: NSObjectProtocol?
    @ObservationIgnored private var audioRenderingModeObserver: NSObjectProtocol?
    @ObservationIgnored private var playerStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var playerTimeControlStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var playerWaitingReasonObservation: NSKeyValueObservation?
    @ObservationIgnored private var playerDefaultRateObservation: NSKeyValueObservation?
    @ObservationIgnored private var playerRateObservation: NSKeyValueObservation?
    @ObservationIgnored private var playerItemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timelineTask: Task<Void, Never>?
    @ObservationIgnored private var initialSeekTask: Task<Void, Never>?
    @ObservationIgnored private var mediaSelectionInspectionTask: Task<Void, Never>?
    @ObservationIgnored private var mediaFactsInspectionTask: Task<Void, Never>?
    @ObservationIgnored private var playbackMetricsTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var chapterArtworkTask: Task<Void, Never>?
    @ObservationIgnored private var contentProposalTask: Task<Void, Never>?
    @ObservationIgnored private var contentProposalEligibilityTask: Task<Void, Never>?
    @ObservationIgnored private var mediaSelectionReconfigurationTask: Task<Void, Never>?
    @ObservationIgnored private var queueNavigationTask: Task<Void, Never>?
    @ObservationIgnored private var queueMutationTask: Task<Void, Never>?
    @ObservationIgnored private var rewindOnResumeTask: Task<Void, Never>?
    @ObservationIgnored private var sleepTimerTask: Task<Void, Never>?
    @ObservationIgnored private var rewindOnResumeTimeJumpToken:
        PlexPlaybackTimeJumpExpectations.Token?
    @ObservationIgnored private var preparationEpoch = PlexPlaybackSessionEpoch()
    @ObservationIgnored private var preparingRequestID: UUID?
    @ObservationIgnored private var timelineCadence = PlexTimelineReportCadence()
    @ObservationIgnored private var timelineReporter: PlexTimelineReportSequencer?
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var publishedNowPlayingItemIdentifier: ObjectIdentifier?
    @ObservationIgnored private var publishedNowPlayingFingerprint:
        PlexNowPlayingMetadata.PublicationFingerprint?
    @ObservationIgnored private var publishedNowPlayingStatus: PlexPlaybackStatus?
    @ObservationIgnored private let userInteractionStore = PlexUserInteractionStore()
    @ObservationIgnored private var hasPrepared = false
    @ObservationIgnored private var postPlayTask: Task<Void, Never>?
    @ObservationIgnored private var upNextRequest: TVPlexPlaybackRequest?
    @ObservationIgnored private var automaticMarkerTransition = PlexAutomaticPlaybackMarkerTransition()
    @ObservationIgnored private var expectedTimeJumps = PlexPlaybackTimeJumpExpectations()
    @ObservationIgnored private var nativeMediaSelectionState = PlexNativeMediaSelectionState()
    @ObservationIgnored private var mediaSelection: PlexPlaybackMediaSelection?
    @ObservationIgnored private var inspectedMediaItemIdentifier: ObjectIdentifier?
    @ObservationIgnored private var deliveredMediaFacts: PlexNativeMediaFacts?
    @ObservationIgnored private var playbackMetricFacts: PlexPlaybackMetricFacts?
    @ObservationIgnored private var waitingReason: PlexPlaybackWaitingReason?
    @ObservationIgnored private var needsInitialSeek = false
    @ObservationIgnored private var currentPlan: PlexPlaybackPlan?
    @ObservationIgnored private var currentRequest: TVPlexPlaybackRequest?
    @ObservationIgnored private weak var currentStore: TVAppStore?
    @ObservationIgnored private var upNextPlaybackRate: PlexPlaybackRate = .normal
    @ObservationIgnored private var proposedNextRequest: TVPlexPlaybackRequest?
    @ObservationIgnored private var preparedContentProposal: AVContentProposal?
    @ObservationIgnored private var authorizedContentProposals: [AVContentProposal] = []
    @ObservationIgnored private var qualitySuggestionState =
        PlexPlaybackQualitySuggestionSessionState()
    @ObservationIgnored private var hasMarkedCurrentItemWatched = false
    @ObservationIgnored private var hasReachedEnd = false
    @ObservationIgnored private var handledEndRequestID: UUID?
    @ObservationIgnored private var hasRejectedContentProposal = false
    @ObservationIgnored private var stoppedTimelineSessionIdentifier: String?
    @ObservationIgnored private var stoppedTimelineContinuing: Bool?
    @ObservationIgnored private var wasPlayingBeforeAudioInterruption = false
    @ObservationIgnored private var pendingRecovery: (
        requestID: UUID,
        request: PlexPlaybackRecoveryRequest,
        playbackRate: PlexPlaybackRate
    )?
    @ObservationIgnored private var failedQueueOperation: TVPlaybackQueueFailureRecovery?

    func prepare(request: TVPlexPlaybackRequest, store: TVAppStore) async {
        if let currentRequest, currentRequest.id != request.id {
            if let currentStore {
                stop(store: currentStore, request: currentRequest)
            } else {
                resetPlayer()
            }
        }
        if let preparingRequestID, preparingRequestID != request.id {
            preparationEpoch.invalidate()
            self.preparingRequestID = nil
            hasPrepared = false
        }
        guard !hasPrepared else { return }
        let preparationTicket = preparationEpoch.activate()
        preparingRequestID = request.id
        hasPrepared = true
        errorMessage = nil
        canRetryPlayback = true
        if pendingRecovery?.requestID != request.id {
            pendingRecovery = nil
        }

        do {
            let recovery = pendingRecovery?.request
            let videoQuality = recovery?.videoQuality
                ?? request.videoQualityOverride
                ?? store.activeVideoQuality
            let playbackRequest = recovery.map {
                request.startingNewPlaybackSession(
                    at: $0.startTime,
                    playbackRate: pendingRecovery?.playbackRate ?? request.playbackRate
                )
            } ?? request
            let plan = try await store.playbackPlan(for: playbackRequest, recovery: recovery)
            try checkCurrentPreparation(
                preparationTicket,
                requestID: request.id
            )
            try configureAudioSession(for: plan.mediaKind)
            let playerItem = makePlayerItem(plan.url)
            PlexNativeSubtitleStyle.apply(to: playerItem, size: store.subtitleSize)
            playerItem.externalMetadata = metadata(for: playbackRequest.item)
            playerItem.navigationMarkerGroups = navigationMarkerGroups(for: playbackRequest.item)
            playerItem.interstitialTimeRanges = interstitialTimeRanges(for: playbackRequest.item)
            let player = AVPlayer(playerItem: playerItem)
            player.defaultRate = playbackRequest.playbackRate.rawValue
            player.preventsDisplaySleepDuringVideoPlayback = plan.mediaKind == .video
            prepareMediaSelection(item: playbackRequest.item, source: plan.source)
            currentPlan = plan
            playbackMethod = plan.method
            supportsAudioBoost = plan.supportsAudioBoost
            supportsSubtitleAutoSync = plan.supportsSubtitleAutoSync
            playbackMediaKind = plan.mediaKind
            audioPresentation = PlexAudioPlaybackPresentation(
                item: playbackRequest.item,
                source: plan.source
            )
            playbackVersionSelection = PlexPlaybackVersionSelection(
                item: playbackRequest.item,
                selectedSource: plan.source
            )
            availableMarkerKinds = PlexPlaybackMarkerAction.availableKinds(
                in: playbackRequest.item.markers,
                duration: playbackRequest.item.durationSeconds
            )
            selectedVideoQuality = videoQuality
            selectedMusicQuality = store.activeMusicQuality
            selectedAudioBoost = store.audioBoost
            currentRequest = playbackRequest
            currentStore = store
            hasMarkedCurrentItemWatched = false
            hasReachedEnd = false
            hasRejectedContentProposal = false
            stoppedTimelineSessionIdentifier = nil
            stoppedTimelineContinuing = nil
            updateQueueControls(for: playbackRequest.queue)
            if repeatMode == .all, !canRepeatAll {
                repeatMode = .off
            }
            queueNavigationErrorMessage = nil
            qualitySuggestionState.moveToItem(itemKey: playbackRequest.item.ratingKey)
            deliveredMediaFacts = nil
            playbackMetricFacts = nil
            waitingReason = nil
            refreshPlaybackInfo()
            pendingRecovery = nil
            installObservers(player: player, request: playbackRequest, store: store)
            self.player = player
            preparationEpoch.invalidate()
            preparingRequestID = nil
            installAudioSessionObservers(for: player)
            activateNowPlaying()
            loadArtwork(for: playbackRequest.item, playerItem: playerItem, store: store)
            loadChapterArtwork(
                for: playbackRequest.item,
                playerItem: playerItem,
                store: store
            )
            prepareNextItem(
                for: playbackRequest,
                playerItem: playerItem,
                store: store
            )
            inspectNativeMediaSelection(for: playerItem)
            observePlaybackState(
                player: player,
                playerItem: playerItem,
                plan: plan,
                request: playbackRequest,
                store: store
            )
            observePlaybackMetrics(of: playerItem, plan: plan)
            scheduleSleepTimer(store.playbackSleepTimer, store: store)
            if plan.startTime > 0 {
                player.pause()
                updateNowPlaying(force: true)
            } else {
                applyAutoplay(playbackRequest.autoplay, to: player)
                updateNowPlaying(force: true)
                await reportTimelineIfNeeded(force: true)
                guard self.player === player else { return }
                startTimelineReporting()
            }
        } catch is CancellationError {
            guard isCurrentPreparation(preparationTicket, requestID: request.id) else {
                return
            }
            preparationEpoch.invalidate()
            preparingRequestID = nil
            hasPrepared = false
            deactivateAudioSession()
        } catch {
            guard isCurrentPreparation(preparationTicket, requestID: request.id) else {
                return
            }
            preparationEpoch.invalidate()
            preparingRequestID = nil
            hasPrepared = false
            deactivateAudioSession()
            errorMessage = error.localizedDescription
        }
    }

    func retry(request: TVPlexPlaybackRequest, store: TVAppStore) async {
        await prepare(request: request, store: store)
    }

    func scenePhaseDidChange(_ phase: ScenePhase) {
        guard player != nil else { return }
        switch phase {
        case .active:
            recordUserInteraction()
            if let currentStore {
                scheduleSleepTimer(currentStore.playbackSleepTimer, store: currentStore)
            }
            Task { await reportTimelineIfNeeded(force: true) }
        case .inactive, .background:
            Task { await reportTimelineIfNeeded(force: true) }
        @unknown default:
            break
        }
    }

    func recordUserInteraction() {
        userInteractionStore.recordInteraction()
        refreshContentProposalEligibility()
    }

    func shouldHandleNativePlayPausePress() -> Bool {
        PlexRewindOnResumePolicy.shouldInterceptNativePlayPausePress(
            status: nowPlayingStatus,
            hasPendingRewind: rewindOnResumeTask != nil,
            isPlaybackControlBusy: isPlaybackControlBusy,
            preference: currentStore?.rewindOnResume ?? .none
        )
    }

    func handleNativePlayPausePress() -> Bool {
        guard let player else { return false }
        if rewindOnResumeTask != nil {
            cancelPendingRewindOnResume()
            return true
        }
        guard !isPlaybackControlBusy,
              let action = PlexPlaybackTransportAction(status: nowPlayingStatus) else {
            return true
        }

        switch action {
        case .play:
            resumePlaybackWithRewind(player)
        case .pause:
            player.pause()
            refreshWaitingState(for: player)
            updateNowPlaying(force: true)
            Task { await reportTimelineIfNeeded(force: true) }
        }
        return true
    }

    func stop(store: TVAppStore, request: TVPlexPlaybackRequest) {
        guard let player else {
            resetPlayer()
            return
        }
        let playbackRequest = currentRequest ?? request
        let time = playbackPosition(for: player)
        let shouldReportStopped = stoppedTimelineSessionIdentifier
            != playbackRequest.sessionIdentifier
        if shouldReportStopped {
            stoppedTimelineSessionIdentifier = playbackRequest.sessionIdentifier
            stoppedTimelineContinuing = false
        }
        resetPlayer()
        guard shouldReportStopped else { return }
        Task {
            _ = await reportPlayback(
                of: playbackRequest,
                state: .stopped,
                time: time.isFinite ? time : 0,
                continuing: false,
                store: store
            )
        }
    }

    func skipActiveMarker() {
        guard let player,
              let playerItem = player.currentItem,
              let requestID = currentRequest?.id,
              let action = activeMarkerAction else {
            return
        }
        recordUserInteraction()
        let timeJumpToken = expectedTimeJumps.expect(target: action.targetTime)
        player.seek(
            to: CMTime(seconds: action.targetTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self, weak player, weak playerItem] completed in
            Task { @MainActor in
                guard let self else { return }
                guard let player,
                      let playerItem,
                      self.player === player,
                      player.currentItem === playerItem,
                      self.currentRequest?.id == requestID else {
                    self.expectedTimeJumps.cancel(timeJumpToken)
                    return
                }
                guard completed else {
                    self.expectedTimeJumps.cancel(timeJumpToken)
                    return
                }
                self.updateNowPlaying(force: true)
                await self.reportTimelineIfNeeded(force: true, time: action.targetTime)
            }
        }
        activeMarkerAction = nil
    }

    func playNextNow() {
        guard let upNextRequest, let currentStore else { return }
        recordUserInteraction()
        postPlayTask?.cancel()
        contentProposalEligibilityTask?.cancel()
        contentProposalEligibilityTask = nil
        currentStore.presentPlayback(
            upNextRequest.withPlaybackRate(upNextPlaybackRate)
        )
    }

    func cancelPostPlay() {
        guard let player,
              let currentRequest,
              let currentStore else {
            return
        }
        recordUserInteraction()
        postPlayTask?.cancel()
        postPlayTask = nil
        upNextItem = nil
        upNextRequest = nil
        upNextPlaybackRate = .normal
        postPlayCountdown = nil
        isReplacingPlayback = true
        updateNowPlayingControlAvailability()
        Task { [weak self, weak player] in
            guard let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == currentRequest.id,
                  await reportStopped(
                      continuing: false,
                      time: completedPlaybackTime
                  ) else {
                return
            }
            currentStore.dismissPlayer()
        }
    }

    func shouldPresentContentProposal(_ proposal: AVContentProposal) -> Bool {
        guard isAuthorizedContentProposal(proposal),
              player?.currentItem?.nextContentProposal === proposal else {
            return false
        }
        return true
    }

    func acceptContentProposal(_ proposal: AVContentProposal) {
        guard isAuthorizedContentProposal(proposal) else { return }
        guard let player,
              let currentRequest,
              let currentStore,
              let proposedNextRequest else {
            return
        }
        recordUserInteraction()
        let playbackRate = playbackRate(for: player)
        self.proposedNextRequest = nil
        preparedContentProposal = nil
        authorizedContentProposals = []
        contentProposalEligibilityTask?.cancel()
        contentProposalEligibilityTask = nil
        nextItemTitle = nil
        player.currentItem?.nextContentProposal = nil
        isReplacingPlayback = true
        updateNowPlayingControlAvailability()
        Task { [weak self, weak player] in
            guard let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == currentRequest.id else {
                return
            }
            guard await reportStopped(
                continuing: true,
                time: hasReachedEnd ? completedPlaybackTime : nil
            ) else {
                return
            }
            markCurrentItemWatchedIfNeeded(
                currentRequest.item,
                store: currentStore
            )
            currentStore.presentPlayback(
                proposedNextRequest.withPlaybackRate(playbackRate)
            )
        }
    }

    func playNextItem() {
        guard let player,
              let currentRequest,
              let currentStore,
              canGoNext,
              !isNavigatingQueue,
              !isReplacingPlayback else {
            return
        }
        recordUserInteraction()
        let playbackRate = playbackRate(for: player)
        if let proposedNextRequest {
            self.proposedNextRequest = nil
            preparedContentProposal = nil
            authorizedContentProposals = []
            contentProposalEligibilityTask?.cancel()
            contentProposalEligibilityTask = nil
            nextItemTitle = nil
            player.currentItem?.nextContentProposal = nil
            isReplacingPlayback = true
            updateNowPlayingControlAvailability()
            Task { [weak self, weak player] in
                guard let self,
                      let player,
                      self.player === player,
                      self.currentRequest?.id == currentRequest.id else {
                    return
                }
                guard await reportStopped(continuing: true) else {
                    return
                }
                currentStore.presentPlayback(
                    proposedNextRequest.withPlaybackRate(playbackRate)
                )
            }
            return
        }
        navigateQueue(
            .adjacent(.next),
            player: player,
            request: currentRequest,
            store: currentStore
        )
    }

    func playPreviousItem() {
        guard let player,
              let currentRequest,
              let currentStore,
              canGoPrevious,
              !isNavigatingQueue,
              !isReplacingPlayback else {
            return
        }
        recordUserInteraction()
        navigateQueue(
            .adjacent(.previous),
            player: player,
            request: currentRequest,
            store: currentStore
        )
    }

    func playQueuedItem(playQueueItemID: String) {
        guard let player,
              let currentRequest,
              let currentStore,
              currentRequest.queue?.presentation.upcomingItems.contains(where: {
                  $0.playQueueItemID == playQueueItemID
              }) == true,
              !isNavigatingQueue,
              !isReplacingPlayback else {
            return
        }
        recordUserInteraction()
        navigateQueue(
            .item(playQueueItemID),
            player: player,
            request: currentRequest,
            store: currentStore
        )
    }

    func rejectContentProposal(_ proposal: AVContentProposal) {
        guard isAuthorizedContentProposal(proposal) else { return }
        guard let player,
              let currentRequest,
              let currentStore else {
            return
        }
        recordUserInteraction()
        proposedNextRequest = nil
        preparedContentProposal = nil
        authorizedContentProposals = []
        contentProposalEligibilityTask?.cancel()
        contentProposalEligibilityTask = nil
        nextItemTitle = nil
        player.currentItem?.nextContentProposal = nil
        hasRejectedContentProposal = true
        guard hasReachedEnd else { return }
        isReplacingPlayback = true
        updateNowPlayingControlAvailability()
        Task { [weak self, weak player] in
            guard let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == currentRequest.id,
                  await reportStopped(
                      continuing: false,
                      time: completedPlaybackTime
                  ) else {
                return
            }
            currentStore.dismissPlayer()
        }
    }

    func dismissQueueNavigationError() {
        recordUserInteraction()
        queueNavigationErrorMessage = nil
        failedQueueOperation = nil
    }

    func retryQueueOperation() {
        guard let failedQueueOperation,
              let player,
              let currentRequest,
              let currentStore else {
            dismissQueueNavigationError()
            return
        }
        recordUserInteraction()
        queueNavigationErrorMessage = nil
        self.failedQueueOperation = nil

        switch failedQueueOperation {
        case .navigation(let destination):
            navigateQueue(
                destination,
                player: player,
                request: currentRequest,
                store: currentStore
            )
        case .mutation(let mutation):
            mutateQueue(mutation)
        case .completion:
            Task { [weak self, weak player] in
                guard let self, let player,
                      self.player === player,
                      self.currentRequest?.id == currentRequest.id else { return }
                self.handledEndRequestID = nil
                await handlePlaybackEnded(
                    player: player,
                    installedRequest: currentRequest,
                    store: currentStore
                )
            }
        }
    }

    func setRepeatMode(_ repeatMode: PlexPlaybackRepeatMode) {
        guard repeatMode != self.repeatMode,
              !isReplacingPlayback,
              repeatMode != .all || canRepeatAll else {
            return
        }
        recordUserInteraction()
        self.repeatMode = repeatMode
        refreshPreparedNextItem()
    }

    func setSleepTimer(
        _ preset: PlexPlaybackSleepTimerPreset,
        store: TVAppStore
    ) {
        recordUserInteraction()
        store.setPlaybackSleepTimer(preset)
        scheduleSleepTimer(store.playbackSleepTimer, store: store)
    }

    func setShuffled(_ shuffled: Bool) {
        guard let queue = currentRequest?.queue,
              queue.canChangeShuffle,
              queue.isShuffled != shuffled else {
            return
        }
        recordUserInteraction()
        mutateQueue(.shuffled(shuffled))
    }

    func moveQueuedItem(
        playQueueItemID: String,
        direction: PlexPlayQueueItemMoveDirection
    ) {
        guard currentRequest?.queue?.moveRequest(
            for: playQueueItemID,
            direction: direction
        ) != nil else {
            return
        }
        recordUserInteraction()
        mutateQueue(.move(playQueueItemID, direction))
    }

    func removeQueuedItem(playQueueItemID: String) {
        guard currentRequest?.queue?.canRemoveUpcomingItem(
            playQueueItemID: playQueueItemID
        ) == true else {
            return
        }
        recordUserInteraction()
        mutateQueue(.remove(playQueueItemID))
    }

    private func mutateQueue(_ mutation: TVPlaybackQueueMutation) {
        guard let playerItem = player?.currentItem,
              let currentRequest,
              let currentStore,
              !isNavigatingQueue,
              !isMutatingQueue,
              !isReplacingPlayback else {
            return
        }

        let requestID = currentRequest.id
        isMutatingQueue = true
        queueNavigationErrorMessage = nil
        failedQueueOperation = nil
        updateNowPlayingControlAvailability()
        queueMutationTask?.cancel()
        queueMutationTask = Task { [weak self, weak playerItem] in
            guard let self,
                  let playerItem,
                  !Task.isCancelled,
                  self.player?.currentItem === playerItem,
                  self.currentRequest?.id == requestID else {
                return
            }
            do {
                let updatedRequest: TVPlexPlaybackRequest
                switch mutation {
                case .shuffled(let shuffled):
                    updatedRequest = try await currentStore.playbackRequest(
                        bySettingQueueShuffled: shuffled,
                        from: currentRequest
                    )
                case .move(let playQueueItemID, let direction):
                    updatedRequest = try await currentStore.playbackRequest(
                        byMovingQueueItem: playQueueItemID,
                        direction: direction,
                        from: currentRequest
                    )
                case .remove(let playQueueItemID):
                    updatedRequest = try await currentStore.playbackRequest(
                        byRemovingQueueItem: playQueueItemID,
                        from: currentRequest
                    )
                }
                guard !Task.isCancelled,
                      self.player?.currentItem === playerItem,
                      self.currentRequest?.id == requestID else {
                    return
                }
                self.currentRequest = updatedRequest
                isMutatingQueue = false
                updateQueueControls(for: updatedRequest.queue)
                refreshPlaybackInfo()
                updateNowPlayingControlAvailability()
                updateNowPlaying(force: true)
                prepareNextItem(
                    for: updatedRequest,
                    playerItem: playerItem,
                    store: currentStore
                )
            } catch is CancellationError {
                return
            } catch {
                guard self.player?.currentItem === playerItem,
                      self.currentRequest?.id == requestID else {
                    return
                }
                isMutatingQueue = false
                failedQueueOperation = .mutation(mutation)
                queueNavigationErrorMessage = error.localizedDescription
                updateNowPlayingControlAvailability()
            }
        }
    }

    private func navigateQueue(
        _ destination: TVPlaybackQueueDestination,
        player: AVPlayer,
        request: TVPlexPlaybackRequest,
        store: TVAppStore
    ) {
        let requestID = request.id
        let wasPlaying = autoplayAfterReconfiguration(for: player)
        let playbackRate = playbackRate(for: player)
        isNavigatingQueue = true
        queueNavigationErrorMessage = nil
        failedQueueOperation = nil
        player.pause()
        updateNowPlayingControlAvailability()
        updateNowPlaying(force: true)

        queueNavigationTask?.cancel()
        queueNavigationTask = Task { [weak self, weak player] in
            guard let self,
                  let player,
                  !Task.isCancelled,
                  self.player === player,
                  self.currentRequest?.id == requestID else {
                return
            }
            do {
                let nextRequest: TVPlexPlaybackRequest
                switch destination {
                case .adjacent(let direction):
                    nextRequest = try await store.preparedQueueAdvance(
                        from: request,
                        direction: direction,
                        autoplay: true,
                        playbackRate: playbackRate
                    )
                case .item(let playQueueItemID):
                    nextRequest = try await store.preparedQueueSelection(
                        from: request,
                        playQueueItemID: playQueueItemID,
                        autoplay: true,
                        playbackRate: playbackRate
                    )
                }
                guard !Task.isCancelled,
                      self.player === player,
                      self.currentRequest?.id == requestID else {
                    return
                }
                guard await reportStopped(continuing: true) else {
                    return
                }
                guard !Task.isCancelled,
                      self.player === player,
                      self.currentRequest?.id == requestID else {
                    return
                }
                isNavigatingQueue = false
                proposedNextRequest = nil
                player.currentItem?.nextContentProposal = nil
                store.presentPlayback(nextRequest)
            } catch is CancellationError {
                return
            } catch {
                guard self.player === player,
                      self.currentRequest?.id == requestID else {
                    return
                }
                isNavigatingQueue = false
                failedQueueOperation = .navigation(destination)
                queueNavigationErrorMessage = error.localizedDescription
                applyAutoplay(wasPlaying, to: player)
                updateNowPlayingControlAvailability()
                updateNowPlaying(force: true)
            }
        }
    }

    private func updateQueueControls(for queue: PlexPlaybackQueue?) {
        queuePresentation = queue?.presentation
        canGoPrevious = queue?.canMovePrevious == true
        canGoNext = queue?.canMoveNext == true
        previousItemTitle = queue?.previousItem?.title
        nextItemTitle = queue?.nextItem?.title
        canChangeShuffle = queue?.canChangeShuffle == true
        isShuffled = queue?.isShuffled == true
        canRepeatAll = queue?.canRepeatAll == true
    }

    private func refreshPreparedNextItem() {
        contentProposalTask?.cancel()
        contentProposalEligibilityTask?.cancel()
        contentProposalEligibilityTask = nil
        proposedNextRequest = nil
        preparedContentProposal = nil
        authorizedContentProposals = []
        player?.currentItem?.nextContentProposal = nil
        guard repeatMode != .one,
              let playerItem = player?.currentItem,
              let currentRequest,
              let currentStore else {
            return
        }
        prepareNextItem(
            for: currentRequest,
            playerItem: playerItem,
            store: currentStore
        )
    }

    func selectVideoQuality(_ quality: PlexVideoQuality) {
        guard selectedVideoQuality != quality else { return }
        recordUserInteraction()
        qualitySuggestion = nil
        qualitySuggestionState.suppress()
        changeVideoQuality(to: quality)
    }

    func selectMusicQuality(_ quality: PlexMusicQuality) {
        guard selectedMusicQuality != quality,
              !isReconfiguringMediaSelection,
              !isReplacingPlayback,
              !isNavigatingQueue,
              !isMutatingQueue,
              let player,
              let currentRequest,
              let currentStore,
              isMusicPlayback,
              currentStore.connection?.kind != .local else {
            return
        }
        recordUserInteraction()
        let startTime = playbackPosition(for: player)
        let autoplay = autoplayAfterReconfiguration(for: player)
        let playbackRate = playbackRate(for: player)
        isReplacingPlayback = true
        mediaSelectionErrorMessage = nil
        player.pause()
        updateNowPlayingControlAvailability()
        updateNowPlaying(force: true)

        Task { [weak self, weak player] in
            guard let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == currentRequest.id else {
                return
            }
            guard await reportStopped(continuing: nil, time: startTime) else {
                return
            }
            currentStore.changeMusicQuality(
                to: quality,
                for: currentRequest.item,
                queue: currentRequest.queue,
                source: currentPlan?.source,
                queueSourcePreference: currentRequest.queueSourcePreference,
                at: startTime,
                autoplay: autoplay,
                playbackRate: playbackRate,
                videoQualityOverride: currentRequest.videoQualityOverride,
                forceVideoTranscode: currentRequest.forceVideoTranscode
            )
        }
    }

    func selectAudioBoost(_ audioBoost: PlexAudioBoost) {
        guard selectedAudioBoost != audioBoost,
              supportsAudioBoost,
              !isReconfiguringMediaSelection,
              !isReplacingPlayback,
              !isNavigatingQueue,
              !isMutatingQueue,
              let player,
              let currentRequest,
              let currentStore,
              isVideoPlayback else {
            return
        }
        recordUserInteraction()
        let startTime = playbackPosition(for: player)
        let autoplay = autoplayAfterReconfiguration(for: player)
        let playbackRate = playbackRate(for: player)
        isReplacingPlayback = true
        mediaSelectionErrorMessage = nil
        player.pause()
        updateNowPlayingControlAvailability()
        updateNowPlaying(force: true)

        Task { [weak self, weak player] in
            guard let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == currentRequest.id else {
                return
            }
            guard await reportStopped(continuing: nil, time: startTime) else {
                return
            }
            currentStore.changeAudioBoost(
                to: audioBoost,
                for: currentRequest.item,
                queue: currentRequest.queue,
                source: currentPlan?.source,
                queueSourcePreference: currentRequest.queueSourcePreference,
                at: startTime,
                autoplay: autoplay,
                playbackRate: playbackRate,
                videoQualityOverride: currentRequest.videoQualityOverride,
                forceVideoTranscode: currentRequest.forceVideoTranscode
            )
        }
    }

    func setSubtitleAutoSync(_ isEnabled: Bool) {
        guard currentStore?.automaticallySyncSubtitles != isEnabled,
              supportsSubtitleAutoSync,
              !isReconfiguringMediaSelection,
              !isReplacingPlayback,
              !isNavigatingQueue,
              !isMutatingQueue,
              let player,
              let currentRequest,
              let currentStore,
              isVideoPlayback else {
            return
        }
        recordUserInteraction()
        let startTime = playbackPosition(for: player)
        let autoplay = autoplayAfterReconfiguration(for: player)
        let playbackRate = playbackRate(for: player)
        isReplacingPlayback = true
        mediaSelectionErrorMessage = nil
        player.pause()
        updateNowPlayingControlAvailability()
        updateNowPlaying(force: true)

        Task { [weak self, weak player] in
            guard let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == currentRequest.id else {
                return
            }
            guard await reportStopped(continuing: nil, time: startTime) else {
                return
            }
            currentStore.changeSubtitleAutoSync(
                isEnabled: isEnabled,
                for: currentRequest.item,
                queue: currentRequest.queue,
                source: currentPlan?.source,
                queueSourcePreference: currentRequest.queueSourcePreference,
                at: startTime,
                autoplay: autoplay,
                playbackRate: playbackRate,
                videoQualityOverride: currentRequest.videoQualityOverride,
                forceVideoTranscode: currentRequest.forceVideoTranscode
            )
        }
    }

    func selectSubtitleSize(_ subtitleSize: PlexSubtitleSize) {
        guard currentStore?.subtitleSize != subtitleSize,
              !isReconfiguringMediaSelection,
              !isReplacingPlayback,
              !isNavigatingQueue,
              !isMutatingQueue,
              let player,
              let currentRequest,
              let currentStore,
              isVideoPlayback else {
            return
        }
        recordUserInteraction()
        guard hasSelectedSubtitle else {
            currentStore.subtitleSize = subtitleSize
            PlexNativeSubtitleStyle.apply(to: player.currentItem, size: subtitleSize)
            return
        }
        let startTime = playbackPosition(for: player)
        let autoplay = autoplayAfterReconfiguration(for: player)
        let playbackRate = playbackRate(for: player)
        isReplacingPlayback = true
        mediaSelectionErrorMessage = nil
        player.pause()
        updateNowPlayingControlAvailability()
        updateNowPlaying(force: true)

        Task { [weak self, weak player] in
            guard let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == currentRequest.id else {
                return
            }
            guard await reportStopped(continuing: nil, time: startTime) else {
                return
            }
            currentStore.changeSubtitleSize(
                to: subtitleSize,
                for: currentRequest.item,
                queue: currentRequest.queue,
                source: currentPlan?.source,
                queueSourcePreference: currentRequest.queueSourcePreference,
                at: startTime,
                autoplay: autoplay,
                playbackRate: playbackRate,
                videoQualityOverride: currentRequest.videoQualityOverride,
                forceVideoTranscode: currentRequest.forceVideoTranscode
            )
        }
    }

    func setSubtitleOffset(_ milliseconds: Int) {
        guard let selection = subtitleOffsetSelection,
              selection.milliseconds != milliseconds,
              !isReconfiguringMediaSelection,
              !isReplacingPlayback,
              !isNavigatingQueue,
              !isMutatingQueue,
              let player,
              let currentRequest,
              let currentStore,
              isVideoPlayback else {
            return
        }
        recordUserInteraction()
        let requestID = currentRequest.id
        let startTime = playbackPosition(for: player)
        let autoplay = autoplayAfterReconfiguration(for: player)
        let playbackRate = playbackRate(for: player)
        isReconfiguringMediaSelection = true
        mediaSelectionErrorMessage = nil
        updateNowPlayingControlAvailability()
        if autoplay {
            player.pause()
            updateNowPlaying(force: true)
        }

        mediaSelectionReconfigurationTask?.cancel()
        mediaSelectionReconfigurationTask = Task { [weak self, weak player] in
            guard let self,
                  let player,
                  !Task.isCancelled,
                  self.player === player,
                  self.currentRequest?.id == requestID else {
                return
            }
            do {
                let refreshedItem = try await currentStore.setSubtitleOffset(
                    streamID: selection.streamID,
                    milliseconds: milliseconds,
                    for: currentRequest.item
                )
                guard !Task.isCancelled,
                      self.player === player,
                      self.currentRequest?.id == requestID else {
                    return
                }
                guard await reportStopped(continuing: nil, time: startTime) else {
                    return
                }
                guard !Task.isCancelled,
                      self.player === player,
                      self.currentRequest?.id == requestID else {
                    return
                }
                isReconfiguringMediaSelection = false
                updateNowPlayingControlAvailability()
                currentStore.replacePlayback(
                    with: refreshedItem,
                    queue: currentRequest.queue,
                    source: currentPlan?.source,
                    queueSourcePreference: currentRequest.queueSourcePreference,
                    at: startTime,
                    autoplay: autoplay,
                    playbackRate: playbackRate,
                    videoQualityOverride: currentRequest.videoQualityOverride,
                    forceVideoTranscode: currentRequest.forceVideoTranscode
                )
            } catch is CancellationError {
                return
            } catch {
                guard self.player === player,
                      self.currentRequest?.id == requestID else {
                    return
                }
                isReconfiguringMediaSelection = false
                mediaSelectionErrorMessage = error.localizedDescription
                applyAutoplay(autoplay, to: player)
                updateNowPlayingControlAvailability()
                updateNowPlaying(force: true)
            }
        }
    }

    func selectPlaybackVersion(_ mediaIndex: Int) {
        guard let selection = playbackVersionSelection,
              let source = selection.source(for: mediaIndex),
              !isReconfiguringMediaSelection,
              !isReplacingPlayback,
              !isNavigatingQueue,
              !isMutatingQueue,
              let player,
              let currentRequest,
              let currentStore else {
            return
        }
        recordUserInteraction()
        let startTime = playbackPosition(for: player)
        let autoplay = autoplayAfterReconfiguration(for: player)
        let playbackRate = playbackRate(for: player)
        isReplacingPlayback = true
        mediaSelectionErrorMessage = nil
        player.pause()
        updateNowPlayingControlAvailability()
        updateNowPlaying(force: true)

        Task { [weak self, weak player] in
            guard let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == currentRequest.id else {
                return
            }
            guard await reportStopped(continuing: nil, time: startTime) else {
                return
            }
            currentStore.changePlaybackVersion(
                to: source,
                for: currentRequest.item,
                queue: currentRequest.queue,
                queueSourcePreference: currentRequest.queueSourcePreference,
                at: startTime,
                autoplay: autoplay,
                playbackRate: playbackRate,
                videoQualityOverride: currentRequest.videoQualityOverride,
                forceVideoTranscode: currentRequest.forceVideoTranscode
            )
        }
    }

    func acceptQualitySuggestion() {
        guard let suggestion = qualitySuggestion else { return }
        recordUserInteraction()
        qualitySuggestion = nil
        qualitySuggestionState.recordAccepted(suggestion.targetQuality)
        changeVideoQuality(to: suggestion.targetQuality)
    }

    func dismissQualitySuggestion() {
        guard qualitySuggestion != nil else { return }
        recordUserInteraction()
        qualitySuggestion = nil
        qualitySuggestionState.suppress()
    }

    private func changeVideoQuality(to quality: PlexVideoQuality) {
        guard !isReconfiguringMediaSelection,
              !isReplacingPlayback,
              let player,
              let currentRequest,
              let currentStore else { return }
        let startTime = playbackPosition(for: player)
        let autoplay = autoplayAfterReconfiguration(for: player)
        let playbackRate = playbackRate(for: player)
        isReplacingPlayback = true
        player.pause()
        updateNowPlayingControlAvailability()
        updateNowPlaying(force: true)
        Task { [weak self, weak player] in
            guard let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == currentRequest.id else {
                return
            }
            guard await reportStopped(continuing: nil, time: startTime) else {
                return
            }
            currentStore.changeVideoQuality(
                to: quality,
                for: currentRequest.item,
                queue: currentRequest.queue,
                source: currentPlan?.source,
                queueSourcePreference: currentRequest.queueSourcePreference,
                at: startTime,
                autoplay: autoplay,
                playbackRate: playbackRate,
                forceVideoTranscode: currentRequest.forceVideoTranscode
            )
        }
    }

    func setVideoConversionForced(_ forceVideoTranscode: Bool) {
        guard !isReconfiguringMediaSelection,
              !isReplacingPlayback,
              !isNavigatingQueue,
              !isMutatingQueue,
              let player,
              let currentRequest,
              currentRequest.forceVideoTranscode != forceVideoTranscode,
              let currentStore,
              isVideoPlayback,
              !forceVideoTranscode || currentStore.automaticallyAdjustVideoQuality else {
            return
        }
        recordUserInteraction()
        qualitySuggestion = nil
        qualitySuggestionState.suppress()
        let startTime = playbackPosition(for: player)
        let autoplay = autoplayAfterReconfiguration(for: player)
        let playbackRate = playbackRate(for: player)
        isReplacingPlayback = true
        mediaSelectionErrorMessage = nil
        player.pause()
        updateNowPlayingControlAvailability()
        updateNowPlaying(force: true)

        Task { [weak self, weak player] in
            guard let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == currentRequest.id else {
                return
            }
            guard await reportStopped(continuing: nil, time: startTime) else {
                return
            }
            currentStore.changeVideoConversionMode(
                forceVideoTranscode: forceVideoTranscode,
                videoQualityOverride: forceVideoTranscode
                    ? currentRequest.videoQualityOverride
                    : .original,
                for: currentRequest.item,
                queue: currentRequest.queue,
                source: currentPlan?.source,
                queueSourcePreference: currentRequest.queueSourcePreference,
                at: startTime,
                autoplay: autoplay,
                playbackRate: playbackRate
            )
        }
    }

    func restartFromBeginning() {
        guard !isReconfiguringMediaSelection,
              !isReplacingPlayback,
              let player,
              let currentRequest,
              let currentStore else { return }
        recordUserInteraction()
        let autoplay = autoplayAfterReconfiguration(for: player)
        let playbackRate = playbackRate(for: player)
        isReplacingPlayback = true
        player.pause()
        updateNowPlayingControlAvailability()
        updateNowPlaying(force: true)
        Task { [weak self, weak player] in
            guard let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == currentRequest.id else {
                return
            }
            guard await reportStopped(continuing: nil) else {
                return
            }
            currentStore.restartPlayback(
                of: currentRequest.item,
                queue: currentRequest.queue,
                source: currentPlan?.source,
                queueSourcePreference: currentRequest.queueSourcePreference,
                autoplay: autoplay,
                playbackRate: playbackRate,
                videoQualityOverride: currentRequest.videoQualityOverride,
                forceVideoTranscode: currentRequest.forceVideoTranscode
            )
        }
    }

    func selectAudioStream(_ streamID: Int) {
        guard serverManagedMediaSelection.canSelectAudioStream(streamID) else { return }
        recordUserInteraction()
        reconfigureMediaSelection(audioStreamID: streamID)
    }

    func selectSubtitleStream(_ streamID: Int?) {
        guard serverManagedMediaSelection.canSelectSubtitleStream(streamID) else { return }
        recordUserInteraction()
        reconfigureMediaSelection(subtitleStreamID: streamID ?? 0)
    }

    func dismissMediaSelectionError() {
        recordUserInteraction()
        mediaSelectionErrorMessage = nil
    }

    private func installObservers(
        player: AVPlayer,
        request: TVPlexPlaybackRequest,
        store: TVAppStore
    ) {
        guard let playerItem = player.currentItem else { return }

        positionObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player, weak playerItem] time in
            guard let self, let player, let playerItem else { return }
            Task { @MainActor in
                self.updateMarkerAction(
                    at: time.seconds,
                    player: player,
                    playerItem: playerItem,
                    request: request,
                    store: store
                )
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self, weak player, weak playerItem] _ in
            Task { @MainActor in
                guard let self,
                      let player,
                      let playerItem,
                      self.player === player,
                      player.currentItem === playerItem,
                      self.currentRequest?.id == request.id else {
                    return
                }
                await self.handlePlaybackEnded(
                    player: player,
                    installedRequest: request,
                    store: store
                )
            }
        }

        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self, weak player, weak playerItem] notification in
            let notificationMessage = (
                notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
                    as? Error
            )?.localizedDescription
            Task { @MainActor in
                guard let self,
                      let player,
                      let playerItem,
                      self.player === player,
                      player.currentItem === playerItem,
                      self.currentRequest?.id == request.id else {
                    return
                }
                self.failPlayback(
                    message: notificationMessage
                        ?? player.currentItem?.error?.localizedDescription
                        ?? "Apple TV could no longer play this Plex stream.",
                    player: player,
                    request: request,
                    store: store
                )
            }
        }

        timeJumpObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.timeJumpedNotification,
            object: playerItem,
            queue: .main
        ) { [weak self, weak player, weak playerItem] _ in
            Task { @MainActor in
                guard let self,
                      let player,
                      let playerItem,
                      self.player === player,
                      player.currentItem === playerItem,
                      self.currentRequest?.id == request.id else {
                    return
                }
                let position = player.currentTime().seconds
                guard position.isFinite,
                      !self.expectedTimeJumps.consume(position: max(position, 0)) else {
                    return
                }
                self.updateNowPlaying(force: true)
                await self.reportTimelineIfNeeded(force: true, time: position)
            }
        }

        playbackStalledObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: playerItem,
            queue: .main
        ) { [weak self, weak player, weak playerItem] _ in
            Task { @MainActor in
                guard let self,
                      let player,
                      let playerItem,
                      self.player === player,
                      player.currentItem === playerItem,
                      self.currentRequest?.id == request.id else {
                    return
                }
                self.refreshWaitingState(for: player)
                await self.reportTimelineIfNeeded(
                    force: true,
                    stateOverride: .buffering
                )
            }
        }
    }

    private func handlePlaybackEnded(
        player: AVPlayer,
        installedRequest: TVPlexPlaybackRequest,
        store: TVAppStore
    ) async {
        guard self.player === player,
              let currentRequest,
              currentRequest.id == installedRequest.id,
              !isNavigatingQueue,
              !isMutatingQueue,
              !isReplacingPlayback,
              handledEndRequestID != currentRequest.id else {
            return
        }
        handledEndRequestID = currentRequest.id
        timelineTask?.cancel()
        timelineTask = nil
        hasReachedEnd = true
        failedQueueOperation = nil
        queueNavigationErrorMessage = nil
        updateNowPlaying(force: true)
        markCurrentItemWatchedIfNeeded(currentRequest.item, store: store)
        let playbackRate = playbackRate(for: player)

        if store.playbackSleepTimer.stopsAtEndOfItem {
            store.clearPlaybackSleepTimer()
            guard await reportStopped(
                continuing: false,
                time: completedPlaybackTime
            ) else { return }
            store.dismissPlayer()
            return
        }

        if hasRejectedContentProposal {
            guard await reportStopped(
                continuing: false,
                time: completedPlaybackTime
            ) else { return }
            store.dismissPlayer()
            return
        }

        let preflightAction = playbackCompletionAction(
            for: currentRequest,
            canAdvance: proposedNextRequest != nil
                || currentRequest.queue?.canMoveNext == true,
            canResetQueue: currentRequest.queue?.canRepeatAll == true,
            store: store
        )

        if preflightAction == .replayCurrent {
            guard await reportStopped(
                continuing: true,
                time: completedPlaybackTime
            ) else { return }
            store.restartPlayback(
                of: currentRequest.item,
                queue: currentRequest.queue,
                source: currentPlan?.source,
                queueSourcePreference: currentRequest.queueSourcePreference,
                playbackRate: playbackRate,
                videoQualityOverride: currentRequest.videoQualityOverride,
                forceVideoTranscode: currentRequest.forceVideoTranscode
            )
            return
        }

        guard player.currentItem?.nextContentProposal == nil else {
            return
        }

        if preflightAction == .resetQueue {
            do {
                let repeatedRequest = try await store.preparedRepeatedQueue(
                    from: currentRequest,
                    playbackRate: playbackRate
                )
                guard self.player === player,
                      self.currentRequest?.id == currentRequest.id else {
                    return
                }
                guard await reportStopped(
                    continuing: true,
                    time: completedPlaybackTime
                ) else { return }
                store.presentPlayback(
                    repeatedRequest.withPlaybackRate(playbackRate)
                )
            } catch is CancellationError {
                return
            } catch {
                guard self.player === player,
                      self.currentRequest?.id == currentRequest.id else {
                    return
                }
                guard await reportStopped(
                    continuing: false,
                    time: completedPlaybackTime
                ) else { return }
                failedQueueOperation = .completion
                queueNavigationErrorMessage = error.localizedDescription
            }
            return
        }

        do {
            let nextRequest: TVPlexPlaybackRequest?
            if let proposedNextRequest {
                nextRequest = proposedNextRequest
            } else {
                nextRequest = try await store.preparedNextPlayback(
                    after: currentRequest,
                    playbackRate: playbackRate
                )
            }
            guard self.player === player,
                  self.currentRequest?.id == currentRequest.id else {
                return
            }
            let completionAction = playbackCompletionAction(
                for: currentRequest,
                canAdvance: nextRequest != nil,
                canResetQueue: false,
                store: store
            )
            guard let nextRequest else {
                guard await reportStopped(
                    continuing: false,
                    time: completedPlaybackTime
                ) else { return }
                store.dismissPlayer()
                return
            }
            guard await reportStopped(
                continuing: true,
                time: completedPlaybackTime
            ) else { return }
            switch completionAction {
            case .advanceNext:
                store.presentPlayback(nextRequest.withPlaybackRate(playbackRate))
            case .presentPostPlay(let autoAdvanceAfterSeconds):
                let presentationMode = PlexPostPlayPresentationMode.resolve(
                    action: completionAction,
                    autoplayPreferences: store.autoplayPreferences
                )
                startPostPlay(
                    nextRequest: nextRequest,
                    playbackRate: playbackRate,
                    autoAdvanceAfterSeconds: autoAdvanceAfterSeconds,
                    presentationMode: presentationMode,
                    store: store
                )
            case .stop:
                store.dismissPlayer()
            case .replayCurrent, .resetQueue:
                assertionFailure("Playback completion preflight handled this action.")
                store.dismissPlayer()
            }
        } catch is CancellationError {
            return
        } catch {
            guard self.player === player,
                  self.currentRequest?.id == currentRequest.id else {
                return
            }
            guard await reportStopped(
                continuing: false,
                time: completedPlaybackTime
            ) else { return }
            failedQueueOperation = .completion
            queueNavigationErrorMessage = error.localizedDescription
        }
    }

    private func startPostPlay(
        nextRequest: TVPlexPlaybackRequest,
        playbackRate: PlexPlaybackRate,
        autoAdvanceAfterSeconds: Int?,
        presentationMode: PlexPostPlayPresentationMode,
        store: TVAppStore
    ) {
        postPlayTask?.cancel()
        contentProposalEligibilityTask?.cancel()
        contentProposalEligibilityTask = nil
        preparedContentProposal = nil
        authorizedContentProposals = []
        player?.currentItem?.nextContentProposal = nil
        upNextItem = nextRequest.item
        upNextRequest = nextRequest
        upNextPlaybackRate = playbackRate
        postPlayTitle = presentationMode == .inactivityConfirmation
            ? "Are You Still Watching?"
            : "Up Next"
        postPlayCountdown = autoAdvanceAfterSeconds
        guard let autoAdvanceAfterSeconds else {
            postPlayTask = nil
            return
        }
        guard let player,
              let requestID = currentRequest?.id else {
            return
        }
        postPlayTask = Task { [weak self, weak player] in
            for seconds in stride(from: autoAdvanceAfterSeconds, through: 1, by: -1) {
                guard !Task.isCancelled,
                      let self,
                      let player,
                      self.player === player,
                      self.currentRequest?.id == requestID else {
                    return
                }
                postPlayCountdown = seconds
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled,
                  let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == requestID else {
                return
            }
            store.presentPlayback(nextRequest.withPlaybackRate(playbackRate))
        }
    }

    private func playbackCompletionAction(
        for request: TVPlexPlaybackRequest,
        canAdvance: Bool,
        canResetQueue: Bool,
        store: TVAppStore
    ) -> PlexPlaybackCompletionAction {
        PlexPlaybackCompletionAction.resolve(
            repeatMode: repeatMode,
            canAdvance: canAdvance,
            canResetQueue: canResetQueue,
            completedItem: request.item,
            mediaKind: currentPlan?.mediaKind ?? .video,
            duration: currentPlan?.duration ?? request.item.durationSeconds,
            autoplayPreferences: store.autoplayPreferences,
            lastInteractionDate: userInteractionStore.lastInteractionDate,
            isCinemaPreplayItem: request.queue?.isCurrentCinemaPreplayItem == true
        )
    }

    private func resetPlayer() {
        preparationEpoch.invalidate()
        preparingRequestID = nil
        removePlaybackStateObservations()
        mediaSelectionInspectionTask?.cancel()
        mediaSelectionInspectionTask = nil
        mediaFactsInspectionTask?.cancel()
        mediaFactsInspectionTask = nil
        playbackMetricsTask?.cancel()
        playbackMetricsTask = nil
        artworkTask?.cancel()
        artworkTask = nil
        chapterArtworkTask?.cancel()
        chapterArtworkTask = nil
        contentProposalTask?.cancel()
        contentProposalTask = nil
        contentProposalEligibilityTask?.cancel()
        contentProposalEligibilityTask = nil
        inspectedMediaItemIdentifier = nil
        deliveredMediaFacts = nil
        playbackMetricFacts = nil
        waitingReason = nil
        playbackMediaKind = .video
        audioPresentation = nil
        playbackVersionSelection = nil
        availableMarkerKinds = []
        qualitySuggestion = nil
        mediaSelectionReconfigurationTask?.cancel()
        mediaSelectionReconfigurationTask = nil
        queueNavigationTask?.cancel()
        queueNavigationTask = nil
        queueMutationTask?.cancel()
        queueMutationTask = nil
        rewindOnResumeTask?.cancel()
        rewindOnResumeTask = nil
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        if let rewindOnResumeTimeJumpToken {
            expectedTimeJumps.cancel(rewindOnResumeTimeJumpToken)
            self.rewindOnResumeTimeJumpToken = nil
        }
        timelineTask?.cancel()
        timelineTask = nil
        timelineCadence.reset()
        postPlayTask?.cancel()
        postPlayTask = nil
        upNextItem = nil
        upNextRequest = nil
        upNextPlaybackRate = .normal
        postPlayTitle = "Up Next"
        proposedNextRequest = nil
        preparedContentProposal = nil
        authorizedContentProposals = []
        canGoPrevious = false
        canGoNext = false
        previousItemTitle = nil
        nextItemTitle = nil
        queuePresentation = nil
        isNavigatingQueue = false
        isMutatingQueue = false
        isReplacingPlayback = false
        canChangeShuffle = false
        isShuffled = false
        canRepeatAll = false
        queueNavigationErrorMessage = nil
        failedQueueOperation = nil
        postPlayCountdown = nil
        activeMarkerAction = nil
        mediaSelection = nil
        nativeMediaSelectionState.beginReload()
        serverManagedMediaSelection = PlexServerManagedMediaSelection()
        isReconfiguringMediaSelection = false
        mediaSelectionErrorMessage = nil
        playbackInfo = nil
        automaticMarkerTransition.reset()
        expectedTimeJumps.invalidate()
        if let player {
            player.currentItem?.nowPlayingInfo = nil
            player.pause()
            removeObservers(from: player)
            player.replaceCurrentItem(with: nil)
        }
        nowPlayingArtwork = nil
        publishedNowPlayingItemIdentifier = nil
        publishedNowPlayingFingerprint = nil
        publishedNowPlayingStatus = nil
        removeAudioSessionObservers()
        player = nil
        currentPlan = nil
        playbackMethod = nil
        selectedVideoQuality = nil
        selectedMusicQuality = nil
        selectedAudioBoost = nil
        supportsAudioBoost = false
        supportsSubtitleAutoSync = false
        subtitleOffsetSelection = nil
        currentRequest = nil
        currentStore = nil
        hasPrepared = false
        hasMarkedCurrentItemWatched = false
        hasReachedEnd = false
        handledEndRequestID = nil
        hasRejectedContentProposal = false
        deactivateAudioSession()
    }

    private func scheduleSleepTimer(
        _ timer: PlexPlaybackSleepTimer,
        store: TVAppStore
    ) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        guard let remainingTime = timer.remainingTime(),
              let player,
              let requestID = currentRequest?.id else {
            return
        }

        sleepTimerTask = Task { [weak self, weak player] in
            if remainingTime > 0 {
                do {
                    try await Task.sleep(for: .seconds(remainingTime))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled,
                  let self,
                  let player,
                  self.player === player,
                  self.currentRequest?.id == requestID,
                  store.playbackSleepTimer == timer else {
                return
            }
            await self.stopForSleepTimer(
                player: player,
                requestID: requestID,
                store: store
            )
        }
    }

    private func stopForSleepTimer(
        player: AVPlayer,
        requestID: UUID,
        store: TVAppStore
    ) async {
        guard self.player === player,
              currentRequest?.id == requestID,
              store.playbackSleepTimer.isActive else {
            return
        }
        isReplacingPlayback = true
        updateNowPlayingControlAvailability()
        guard await reportStopped(continuing: false) else { return }
        store.clearPlaybackSleepTimer()
        store.dismissPlayer()
    }

    private func isCurrentPreparation(
        _ ticket: PlexPlaybackSessionEpoch.Ticket,
        requestID: UUID
    ) -> Bool {
        preparingRequestID == requestID && preparationEpoch.isCurrent(ticket)
    }

    private func checkCurrentPreparation(
        _ ticket: PlexPlaybackSessionEpoch.Ticket,
        requestID: UUID
    ) throws {
        try Task.checkCancellation()
        guard isCurrentPreparation(ticket, requestID: requestID) else {
            throw CancellationError()
        }
    }

    private func prepareMediaSelection(item: PlexMediaItem, source: PlexPlaybackSource) {
        mediaSelectionInspectionTask?.cancel()
        nativeMediaSelectionState.beginReload()
        mediaSelection = PlexPlaybackMediaSelection(item: item, source: source)
        subtitleOffsetSelection = mediaSelection?.subtitleOffsetSelection
        serverManagedMediaSelection = PlexServerManagedMediaSelection()
    }

    private func inspectNativeMediaSelection(for playerItem: AVPlayerItem) {
        let generation = nativeMediaSelectionState.generation
        mediaSelectionInspectionTask = Task { [weak self, weak playerItem] in
            guard let self, let playerItem else { return }
            do {
                let availability = try await PlexNativeMediaInspector
                    .mediaSelectionAvailability(asset: playerItem.asset)
                guard !Task.isCancelled,
                      self.player?.currentItem === playerItem,
                      let mediaSelection else {
                    return
                }
                guard nativeMediaSelectionState.accept(availability, generation: generation) else {
                    return
                }
                serverManagedMediaSelection = PlexServerManagedMediaSelection(
                    selection: mediaSelection,
                    nativeAvailability: availability
                )
                updateNowPlaying(force: true)
            } catch {
                return
            }
        }
    }

    private func reconfigureMediaSelection(
        audioStreamID: Int? = nil,
        subtitleStreamID: Int? = nil
    ) {
        guard !isReconfiguringMediaSelection,
              audioStreamID != nil || subtitleStreamID != nil,
              let partID = mediaSelection?.partID,
              let player,
              let currentRequest,
              let currentStore else {
            return
        }

        let requestID = currentRequest.id
        let startTime = playbackPosition(for: player)
        let autoplay = autoplayAfterReconfiguration(for: player)
        let playbackRate = playbackRate(for: player)
        isReconfiguringMediaSelection = true
        mediaSelectionErrorMessage = nil
        updateNowPlayingControlAvailability()
        if autoplay {
            player.pause()
            updateNowPlaying(force: true)
        }

        mediaSelectionReconfigurationTask?.cancel()
        mediaSelectionReconfigurationTask = Task { [weak self, weak player] in
            guard let self,
                  let player,
                  !Task.isCancelled,
                  self.player === player,
                  self.currentRequest?.id == requestID else {
                return
            }
            do {
                let refreshedItem = try await currentStore.selectMediaStreams(
                    partID: partID,
                    audioStreamID: audioStreamID,
                    subtitleStreamID: subtitleStreamID,
                    for: currentRequest.item
                )
                guard !Task.isCancelled,
                      self.player === player,
                      self.currentRequest?.id == requestID else {
                    return
                }
                guard await reportStopped(continuing: nil, time: startTime) else {
                    return
                }
                guard !Task.isCancelled,
                      self.player === player,
                      self.currentRequest?.id == requestID else {
                    return
                }
                isReconfiguringMediaSelection = false
                updateNowPlayingControlAvailability()
                currentStore.replacePlayback(
                    with: refreshedItem,
                    queue: currentRequest.queue,
                    source: currentPlan?.source,
                    queueSourcePreference: currentRequest.queueSourcePreference,
                    at: startTime,
                    autoplay: autoplay,
                    playbackRate: playbackRate,
                    videoQualityOverride: currentRequest.videoQualityOverride,
                    forceVideoTranscode: currentRequest.forceVideoTranscode
                )
            } catch is CancellationError {
                return
            } catch {
                guard self.player === player,
                      self.currentRequest?.id == requestID else {
                    return
                }
                isReconfiguringMediaSelection = false
                mediaSelectionErrorMessage = error.localizedDescription
                applyAutoplay(autoplay, to: player)
                updateNowPlayingControlAvailability()
                updateNowPlaying(force: true)
            }
        }
    }

    private func removeObservers(from player: AVPlayer) {
        if let positionObserver {
            player.removeTimeObserver(positionObserver)
            self.positionObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
        if let timeJumpObserver {
            NotificationCenter.default.removeObserver(timeJumpObserver)
            self.timeJumpObserver = nil
        }
        if let playbackStalledObserver {
            NotificationCenter.default.removeObserver(playbackStalledObserver)
            self.playbackStalledObserver = nil
        }
    }

    private func installAudioSessionObservers(for player: AVPlayer) {
        removeAudioSessionObservers()
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self, weak player] notification in
            guard let event = TVAudioInterruptionEvent(notification: notification) else {
                return
            }
            Task { @MainActor in
                guard let self,
                      let player,
                      self.player === player else {
                    return
                }
                self.handleAudioInterruption(event, player: player)
            }
        }

        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self,
                      let player,
                      self.player === player,
                      let request = self.currentRequest,
                      let store = self.currentStore else {
                    return
                }
                self.failPlayback(
                    message: "Apple TV’s media services restarted. Try again to resume playback.",
                    player: player,
                    request: request,
                    store: store
                )
            }
        }

        audioRenderingModeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.renderingModeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self,
                      let player,
                      self.player === player else {
                    return
                }
                self.refreshPlaybackInfo()
            }
        }
    }

    private func removeAudioSessionObservers() {
        if let audioInterruptionObserver {
            NotificationCenter.default.removeObserver(audioInterruptionObserver)
            self.audioInterruptionObserver = nil
        }
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
            self.mediaServicesResetObserver = nil
        }
        if let audioRenderingModeObserver {
            NotificationCenter.default.removeObserver(audioRenderingModeObserver)
            self.audioRenderingModeObserver = nil
        }
        wasPlayingBeforeAudioInterruption = false
    }

    private func handleAudioInterruption(
        _ event: TVAudioInterruptionEvent,
        player: AVPlayer
    ) {
        switch event {
        case .began:
            wasPlayingBeforeAudioInterruption = player.timeControlStatus != .paused
            player.pause()
            updateNowPlaying(force: true)
            Task { await reportTimelineIfNeeded(force: true) }
        case .ended(let systemAllowsResume):
            let shouldResume = wasPlayingBeforeAudioInterruption
                && systemAllowsResume
            wasPlayingBeforeAudioInterruption = false
            applyAutoplay(shouldResume, to: player)
            updateNowPlaying(force: true)
            Task { await reportTimelineIfNeeded(force: true) }
        }
    }

    private func observePlaybackState(
        player: AVPlayer,
        playerItem: AVPlayerItem,
        plan: PlexPlaybackPlan,
        request: TVPlexPlaybackRequest,
        store: TVAppStore
    ) {
        removePlaybackStateObservations()
        needsInitialSeek = plan.startTime > 0
        pendingInitialSeekPosition = needsInitialSeek ? plan.startTime : nil

        playerStatusObservation = player.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self, weak playerItem] observedPlayer, _ in
            Task { @MainActor in
                guard let self, let playerItem else { return }
                self.handlePlayerStateChange(
                    player: observedPlayer,
                    playerItem: playerItem,
                    request: request,
                    store: store
                )
            }
        }

        playerTimeControlStatusObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self, weak playerItem] observedPlayer, _ in
            Task { @MainActor in
                guard let self, let playerItem else { return }
                self.handlePlayerStateChange(
                    player: observedPlayer,
                    playerItem: playerItem,
                    request: request,
                    store: store
                )
            }
        }

        playerWaitingReasonObservation = player.observe(
            \.reasonForWaitingToPlay,
            options: [.initial, .new]
        ) { [weak self, weak playerItem] observedPlayer, _ in
            Task { @MainActor in
                guard let self, let playerItem else { return }
                self.handlePlayerStateChange(
                    player: observedPlayer,
                    playerItem: playerItem,
                    request: request,
                    store: store
                )
            }
        }

        playerDefaultRateObservation = player.observe(
            \.defaultRate,
            options: [.initial, .new]
        ) { [weak self, weak playerItem] observedPlayer, _ in
            Task { @MainActor in
                guard let self, let playerItem else { return }
                self.handlePlayerStateChange(
                    player: observedPlayer,
                    playerItem: playerItem,
                    request: request,
                    store: store
                )
            }
        }

        playerRateObservation = player.observe(
            \.rate,
            options: [.initial, .new]
        ) { [weak self, weak playerItem] observedPlayer, _ in
            Task { @MainActor in
                guard let self, let playerItem else { return }
                self.handlePlayerStateChange(
                    player: observedPlayer,
                    playerItem: playerItem,
                    request: request,
                    store: store,
                    forceNowPlayingUpdate: true
                )
            }
        }

        playerItemStatusObservation = playerItem.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self, weak player] observedItem, _ in
            Task { @MainActor in
                guard let self, let player else { return }
                self.handlePlayerItemStatusChange(
                    player: player,
                    playerItem: observedItem,
                    plan: plan,
                    request: request,
                    store: store
                )
            }
        }
    }

    private func removePlaybackStateObservations() {
        playerStatusObservation?.invalidate()
        playerStatusObservation = nil
        playerTimeControlStatusObservation?.invalidate()
        playerTimeControlStatusObservation = nil
        playerWaitingReasonObservation?.invalidate()
        playerWaitingReasonObservation = nil
        playerDefaultRateObservation?.invalidate()
        playerDefaultRateObservation = nil
        playerRateObservation?.invalidate()
        playerRateObservation = nil
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        initialSeekTask?.cancel()
        initialSeekTask = nil
        needsInitialSeek = false
        pendingInitialSeekPosition = nil
    }

    private func handlePlayerStateChange(
        player: AVPlayer,
        playerItem: AVPlayerItem,
        request: TVPlexPlaybackRequest,
        store: TVAppStore,
        forceNowPlayingUpdate: Bool = false
    ) {
        guard self.player === player,
              player.currentItem === playerItem,
              currentRequest?.id == request.id else {
            return
        }
        if let message = playbackFailureMessage(player: player, item: playerItem) {
            failPlayback(
                message: message,
                player: player,
                request: request,
                store: store
            )
            return
        }
        refreshWaitingState(for: player)
        updateNowPlaying(force: forceNowPlayingUpdate)
    }

    private func handlePlayerItemStatusChange(
        player: AVPlayer,
        playerItem: AVPlayerItem,
        plan: PlexPlaybackPlan,
        request: TVPlexPlaybackRequest,
        store: TVAppStore
    ) {
        guard self.player === player,
              player.currentItem === playerItem,
              currentRequest?.id == request.id else {
            return
        }
        if let message = playbackFailureMessage(player: player, item: playerItem) {
            failPlayback(
                message: message,
                player: player,
                request: request,
                store: store
            )
            return
        }

        updateNowPlayingControlAvailability()
        refreshWaitingState(for: player)
        updateNowPlaying()

        guard playerItem.status == .readyToPlay else { return }
        inspectDeliveredMediaIfNeeded(for: playerItem)
        startInitialSeekIfNeeded(
            player: player,
            playerItem: playerItem,
            plan: plan,
            request: request,
            store: store
        )
    }

    private func startInitialSeekIfNeeded(
        player: AVPlayer,
        playerItem: AVPlayerItem,
        plan: PlexPlaybackPlan,
        request: TVPlexPlaybackRequest,
        store: TVAppStore
    ) {
        guard needsInitialSeek else { return }
        needsInitialSeek = false
        initialSeekTask?.cancel()
        initialSeekTask = Task { [weak self, weak player, weak playerItem] in
            guard let self, let player, let playerItem else { return }
            let token = expectedTimeJumps.expect(target: plan.startTime)
            let completed = await player.seek(
                to: CMTime(seconds: plan.startTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            guard !Task.isCancelled,
                  self.player === player,
                  player.currentItem === playerItem else {
                expectedTimeJumps.cancel(token)
                return
            }
            guard completed else {
                expectedTimeJumps.cancel(token)
                failPlayback(
                    message: "Apple TV could not resume this stream at the saved position.",
                    player: player,
                    request: request,
                    store: store
                )
                return
            }
            pendingInitialSeekPosition = nil
            applyAutoplay(request.autoplay, to: player)
            updateNowPlayingControlAvailability()
            updateNowPlaying(force: true)
            await reportTimelineIfNeeded(force: true, time: plan.startTime)
            guard !Task.isCancelled, self.player === player else { return }
            initialSeekTask = nil
            startTimelineReporting()
        }
    }

    private func inspectDeliveredMediaIfNeeded(for playerItem: AVPlayerItem) {
        let identifier = ObjectIdentifier(playerItem)
        guard inspectedMediaItemIdentifier != identifier else { return }
        inspectedMediaItemIdentifier = identifier
        mediaFactsInspectionTask?.cancel()
        mediaFactsInspectionTask = Task { [weak self, weak playerItem] in
            guard let self, let playerItem else { return }
            let facts = await PlexNativeMediaInspector.inspect(item: playerItem)
            guard !Task.isCancelled,
                  self.player?.currentItem === playerItem,
                  currentRequest != nil,
                  currentPlan != nil,
                  selectedVideoQuality != nil else {
                return
            }
            deliveredMediaFacts = facts
            refreshPlaybackInfo()
        }
    }

    private func refreshWaitingState(for player: AVPlayer) {
        let waitingReason = PlexPlaybackWaitingReason(
            timeControlStatus: player.timeControlStatus,
            nativeReason: player.reasonForWaitingToPlay
        )
        guard waitingReason != self.waitingReason else { return }
        self.waitingReason = waitingReason
        refreshPlaybackInfo()
    }

    private func refreshPlaybackInfo() {
        guard let currentRequest,
              let currentPlan,
              let selectedVideoQuality else {
            if playbackInfo != nil {
                playbackInfo = nil
            }
            return
        }
        let presentation = PlexPlaybackInfoPresentation(
            item: currentRequest.item,
            deliveryLabel: currentPlan.method.label,
            connectionLabel: currentStore?.connection?.kind.displayName,
            videoQualityLabel: currentPlan.mediaKind == .video
                ? selectedVideoQuality.label
                : nil,
            playbackVersionLabel: playbackVersionSelection?.selectedOption?.label,
            queuePositionLabel: currentRequest.queue.map {
                "\($0.presentation.currentPosition) of \($0.presentation.totalCount)"
            },
            waitingReasonLabel: waitingReason?.diagnosticLabel,
            audioOutputLabel: AVAudioSession.sharedInstance().renderingMode.plexLabel,
            deliveredMediaFacts: deliveredMediaFacts,
            playbackMetricFacts: playbackMetricFacts?.diagnosticFacts ?? []
        )
        if presentation != playbackInfo {
            playbackInfo = presentation
        }
    }

    private func observePlaybackMetrics(
        of playerItem: AVPlayerItem,
        plan: PlexPlaybackPlan
    ) {
        playbackMetricsTask?.cancel()
        playbackMetricFacts = nil
        playbackMetricsTask = Task { [weak self, weak playerItem] in
            guard let playerItem else { return }

            let metrics = playerItem.metrics(forType: AVMetricPlayerItemStallEvent.self)
                .chronologicalMerge(
                    with: playerItem.metrics(
                        forType: AVMetricPlayerItemInitialLikelyToKeepUpEvent.self
                    ),
                    playerItem.metrics(forType: AVMetricPlayerItemVariantSwitchEvent.self),
                    playerItem.metrics(forType: AVMetricHLSMediaSegmentRequestEvent.self),
                    playerItem.metrics(forType: AVMetricMediaResourceRequestEvent.self)
                )
            var facts = PlexPlaybackMetricFacts()

            do {
                for try await (event, publisher) in metrics {
                    guard !Task.isCancelled,
                          let self,
                          let publishedItem = publisher as? AVPlayerItem,
                          publishedItem === playerItem,
                          player?.currentItem === playerItem else {
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
                        guard plan.method != .directPlay, plan.mediaKind == .video else {
                            continue
                        }
                        facts.recordBandwidthSample(
                            PlexPlaybackBandwidthSample(segment: event)
                        )
                    case let event as AVMetricMediaResourceRequestEvent:
                        guard plan.method == .directPlay, plan.mediaKind == .video else {
                            continue
                        }
                        facts.recordBandwidthSample(
                            PlexPlaybackBandwidthSample(resourceRequest: event)
                        )
                    default:
                        continue
                    }
                    updatePlaybackMetricFacts(facts)
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func updatePlaybackMetricFacts(_ facts: PlexPlaybackMetricFacts) {
        guard facts != playbackMetricFacts else { return }
        playbackMetricFacts = facts
        refreshPlaybackInfo()
        evaluateQualitySuggestion()
    }

    private func evaluateQualitySuggestion() {
        guard qualitySuggestion == nil,
              !qualitySuggestionState.isSuppressed,
              let currentRequest,
              let currentPlan,
              let selectedVideoQuality,
              let currentStore else {
            return
        }
        let selection = PlexVideoQualitySelection(
            selectedQuality: selectedVideoQuality,
            isVideo: currentPlan.mediaKind == .video,
            canChange: !isReconfiguringMediaSelection
        )
        let sourceBitrate = currentRequest.item.media.indices.contains(
            currentPlan.source.mediaIndex
        ) ? currentRequest.item.media[currentPlan.source.mediaIndex].bitrate : nil
        qualitySuggestion = PlexPlaybackQualitySuggestionPolicy.suggestion(
            isEnabled: currentStore.qualitySuggestionsEnabled
                && !currentStore.automaticallyAdjustVideoQuality,
            selection: selection,
            sourceBitrate: sourceBitrate,
            maximumQuality: currentStore.activeVideoQuality,
            isTranscoding: currentPlan.method == .transcode,
            metrics: playbackMetricFacts,
            excludedQualities: qualitySuggestionState.acceptedQualities
        )
    }

    private func loadArtwork(
        for item: PlexMediaItem,
        playerItem: AVPlayerItem,
        store: TVAppStore
    ) {
        artworkTask?.cancel()
        artworkTask = Task { [weak self, weak playerItem] in
            guard let self,
                  let playerItem,
                  let data = await store.playbackArtworkData(for: item),
                  !Task.isCancelled,
                  self.player?.currentItem === playerItem else {
                return
            }
            let artwork = AVMutableMetadataItem()
            artwork.identifier = .commonIdentifierArtwork
            artwork.value = data as NSData
            playerItem.externalMetadata = playerItem.externalMetadata.filter {
                $0.identifier != .commonIdentifierArtwork
            } + [artwork]
            if let image = await PlexImageDecoder.decodeCGImage(
                from: data,
                maximumPixelSize: 1_200
            )?.image,
               !Task.isCancelled,
               self.player?.currentItem === playerItem {
                nowPlayingArtwork = PlexNowPlayingArtworkFactory.make(from: image)
                updateNowPlaying(force: true)
            }
        }
    }

    private func loadChapterArtwork(
        for item: PlexMediaItem,
        playerItem: AVPlayerItem,
        store: TVAppStore
    ) {
        chapterArtworkTask?.cancel()
        let chapters = PlexPlaybackChapter.chapters(
            from: item.chapters,
            mediaDurationMilliseconds: item.duration
        )
        guard chapters.contains(where: { $0.thumbnailPath != nil }) else {
            chapterArtworkTask = nil
            return
        }

        chapterArtworkTask = Task { [weak self, weak playerItem] in
            guard let self, let playerItem else { return }
            let artwork = await store.playbackChapterArtwork(for: chapters)
            guard !Task.isCancelled,
                  !artwork.isEmpty,
                  self.player?.currentItem === playerItem else {
                return
            }
            playerItem.navigationMarkerGroups = navigationMarkerGroups(
                for: chapters,
                artworkByChapterID: artwork
            )
        }
    }

    private func prepareNextItem(
        for request: TVPlexPlaybackRequest,
        playerItem: AVPlayerItem,
        store: TVAppStore
    ) {
        contentProposalTask?.cancel()
        contentProposalEligibilityTask?.cancel()
        contentProposalEligibilityTask = nil
        preparedContentProposal = nil
        authorizedContentProposals = []
        playerItem.nextContentProposal = nil
        guard repeatMode != .one else {
            proposedNextRequest = nil
            return
        }
        contentProposalTask = Task { [weak self, weak playerItem] in
            guard let self,
                  let playerItem,
                  let nextRequest = try? await store.preparedNextPlayback(
                      after: request,
                      playbackRate: request.playbackRate
                  ),
                  !Task.isCancelled,
                  self.player?.currentItem === playerItem,
                  self.currentRequest?.id == request.id else {
                return
            }

            proposedNextRequest = nextRequest
            canGoNext = true
            nextItemTitle = nextRequest.item.title

            let transitionTime = contentProposalTransitionTime(for: request.item)
            let proposalMetadata = metadata(for: nextRequest.item)
            let proposal = contentProposal(
                for: nextRequest.item,
                transitionTime: transitionTime,
                metadata: proposalMetadata,
                previewImage: nil
            )
            preparedContentProposal = proposal
            authorizedContentProposals = [proposal]
            refreshContentProposalEligibility()

            let artworkData = await store.contentProposalArtworkData(for: nextRequest.item)
            guard !Task.isCancelled,
                  self.player?.currentItem === playerItem,
                  self.currentRequest?.id == request.id,
                  preparedContentProposal === proposal else {
                return
            }
            guard let artworkData,
                  let image = await PlexImageDecoder.decodeCGImage(
                      from: artworkData,
                      maximumPixelSize: 1_280
                  )?.image else {
                return
            }
            guard !Task.isCancelled,
                  self.player?.currentItem === playerItem,
                  self.currentRequest?.id == request.id,
                  preparedContentProposal === proposal,
                  canEnrichContentProposal(
                      transitionTime: transitionTime,
                      playerTime: playerItem.currentTime()
                  ) else {
                return
            }

            let enrichedProposal = contentProposal(
                for: nextRequest.item,
                transitionTime: transitionTime,
                metadata: proposalMetadata,
                previewImage: UIImage(cgImage: image)
            )
            preparedContentProposal = enrichedProposal
            authorizedContentProposals.append(enrichedProposal)
            refreshContentProposalEligibility()
        }
    }

    private func isAuthorizedContentProposal(_ proposal: AVContentProposal) -> Bool {
        proposedNextRequest != nil
            && authorizedContentProposals.contains { $0 === proposal }
    }

    private func contentProposalTransitionTime(for item: PlexMediaItem) -> CMTime {
        let duration = item.duration.map { TimeInterval($0) / 1_000 }
        return PlexPlaybackMarkerAction.creditsStartTime(
            in: item.markers,
            duration: duration
        ).map {
            CMTime(seconds: $0, preferredTimescale: 600)
        } ?? .indefinite
    }

    private func contentProposal(
        for item: PlexMediaItem,
        transitionTime: CMTime,
        metadata: [AVMetadataItem],
        previewImage: UIImage?
    ) -> AVContentProposal {
        let proposal = AVContentProposal(
            contentTimeForTransition: transitionTime,
            title: item.title,
            previewImage: previewImage
        )
        proposal.metadata = metadata
        return proposal
    }

    private func canEnrichContentProposal(
        transitionTime: CMTime,
        playerTime: CMTime
    ) -> Bool {
        let transitionSeconds = transitionTime.seconds
        let playerSeconds = playerTime.seconds
        return !transitionSeconds.isFinite
            || !playerSeconds.isFinite
            || playerSeconds < transitionSeconds
    }

    private func refreshContentProposalEligibility() {
        contentProposalEligibilityTask?.cancel()
        contentProposalEligibilityTask = nil
        guard let playerItem = player?.currentItem,
              let currentRequest,
              let currentStore,
              let preparedContentProposal else {
            return
        }

        let action = playbackCompletionAction(
            for: currentRequest,
            canAdvance: true,
            canResetQueue: false,
            store: currentStore
        )
        let presentationMode = PlexPostPlayPresentationMode.resolve(
            action: action,
            autoplayPreferences: currentStore.autoplayPreferences
        )
        switch presentationMode {
        case .manual:
            preparedContentProposal.automaticAcceptanceInterval = .nan
            playerItem.nextContentProposal = preparedContentProposal
        case .automatic(let autoAdvanceAfterSeconds):
            preparedContentProposal.automaticAcceptanceInterval = TimeInterval(
                autoAdvanceAfterSeconds
            )
            playerItem.nextContentProposal = preparedContentProposal
        case .none, .inactivityConfirmation:
            playerItem.nextContentProposal = nil
        }

        let preferences = currentStore.autoplayPreferences
        let duration = currentPlan?.duration ?? currentRequest.item.durationSeconds
        guard preferences.isEnabled,
              let passoutInterval = preferences.passoutProtection.interval,
              duration > 20 * 60 else {
            return
        }
        let remaining = passoutInterval
            - Date().timeIntervalSince(userInteractionStore.lastInteractionDate)
        guard remaining > 0 else { return }
        let requestID = currentRequest.id
        contentProposalEligibilityTask = Task { [weak self, weak playerItem] in
            try? await Task.sleep(for: .seconds(remaining + 0.1))
            guard !Task.isCancelled,
                  let self,
                  let playerItem,
                  self.player?.currentItem === playerItem,
                  self.currentRequest?.id == requestID else {
                return
            }
            refreshContentProposalEligibility()
        }
    }

    private func markCurrentItemWatchedIfNeeded(
        _ item: PlexMediaItem,
        store: TVAppStore
    ) {
        guard !hasMarkedCurrentItemWatched else { return }
        hasMarkedCurrentItemWatched = true
        Task { await store.markWatched(item) }
    }

    private func playbackFailureMessage(player: AVPlayer, item: AVPlayerItem) -> String? {
        if item.status == .failed {
            return item.error?.localizedDescription ?? "Apple TV could not read this Plex stream."
        }
        if player.status == .failed {
            return player.error?.localizedDescription ?? "Apple TV could no longer play this stream."
        }
        return nil
    }

    private func configureAudioSession(for mediaKind: PlexPlaybackMediaKind) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playback,
            mode: mediaKind == .video ? .moviePlayback : .default,
            policy: .longFormAudio
        )
        try audioSession.setSupportsMultichannelContent(true)
        try audioSession.setActive(true)
        let maximumOutputChannels = audioSession.maximumOutputNumberOfChannels
        if maximumOutputChannels > 0 {
            try audioSession.setPreferredOutputNumberOfChannels(maximumOutputChannels)
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func activateNowPlaying() {
        publishedNowPlayingItemIdentifier = nil
        publishedNowPlayingFingerprint = nil
        publishedNowPlayingStatus = nil
        updateNowPlaying(force: true)
    }

    private func updateNowPlaying(force: Bool = false) {
        guard let playerItem = player?.currentItem,
              let metadata = nowPlayingMetadata else {
            return
        }
        let itemIdentifier = ObjectIdentifier(playerItem)
        let status = nowPlayingStatus
        guard force
            || itemIdentifier != publishedNowPlayingItemIdentifier
            || metadata.publicationFingerprint != publishedNowPlayingFingerprint
            || status != publishedNowPlayingStatus else {
            return
        }

        // AVPlayerViewController owns the tvOS Now Playing session. Supplying
        // item metadata enriches that native session without registering a
        // competing app-global info or remote-command center.
        playerItem.nowPlayingInfo = metadata.nowPlayingInfo(
            artwork: nowPlayingArtwork
        )
        publishedNowPlayingItemIdentifier = itemIdentifier
        publishedNowPlayingFingerprint = metadata.publicationFingerprint
        publishedNowPlayingStatus = status
    }

    private func updateNowPlayingControlAvailability() {
        // AVKit owns transport availability on tvOS. This inexpensive refresh
        // still republishes when an authoritative queue change altered item
        // metadata; ordinary busy-state changes are filtered by the fingerprint.
        updateNowPlaying()
    }

    private func resumePlaybackWithRewind(_ player: AVPlayer) {
        guard let action = PlexRewindOnResumePolicy.action(
            status: nowPlayingStatus,
            position: player.currentTime().seconds,
            preference: currentStore?.rewindOnResume ?? .none
        ) else {
            return
        }

        switch action {
        case .playImmediately:
            player.play()
            refreshWaitingState(for: player)
            updateNowPlaying(force: true)
            Task { await reportTimelineIfNeeded(force: true) }

        case .seekThenPlay(let target):
            cancelPendingRewindOnResume()
            guard let playerItem = player.currentItem,
                  playerItem.status == .readyToPlay else {
                player.play()
                refreshWaitingState(for: player)
                updateNowPlaying(force: true)
                Task { await reportTimelineIfNeeded(force: true) }
                return
            }

            let timeJumpToken = expectedTimeJumps.expect(target: target)
            rewindOnResumeTimeJumpToken = timeJumpToken
            rewindOnResumeTask = Task { [weak self, weak player, weak playerItem] in
                guard let self, let player, let playerItem else { return }
                let completed = await player.seek(
                    to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                guard !Task.isCancelled,
                      self.player === player,
                      player.currentItem === playerItem,
                      self.rewindOnResumeTimeJumpToken == timeJumpToken else {
                    self.expectedTimeJumps.cancel(timeJumpToken)
                    return
                }

                self.rewindOnResumeTask = nil
                self.rewindOnResumeTimeJumpToken = nil
                if !completed {
                    self.expectedTimeJumps.cancel(timeJumpToken)
                }
                player.play()
                self.refreshWaitingState(for: player)
                self.updateNowPlayingControlAvailability()
                self.updateNowPlaying(force: true)
                await self.reportTimelineIfNeeded(force: true)
            }
            updateNowPlayingControlAvailability()
        }
    }

    private func cancelPendingRewindOnResume() {
        guard rewindOnResumeTask != nil || rewindOnResumeTimeJumpToken != nil else {
            return
        }
        rewindOnResumeTask?.cancel()
        rewindOnResumeTask = nil
        player?.currentItem?.cancelPendingSeeks()
        expectedTimeJumps.cancel(rewindOnResumeTimeJumpToken)
        rewindOnResumeTimeJumpToken = nil
        updateNowPlayingControlAvailability()
    }

    private var nowPlayingMetadata: PlexNowPlayingMetadata? {
        guard let currentRequest else { return nil }
        let queue = currentRequest.queue?.presentation
        let position = player.map { playbackPosition(for: $0) } ?? 0
        return PlexNowPlayingMetadata(
            item: currentRequest.item,
            duration: currentPlan?.duration ?? currentRequest.item.durationSeconds,
            elapsedTime: position.isFinite ? max(position, 0) : 0,
            playbackRate: nowPlayingStatus == .playing ? Double(player?.rate ?? 0) : 0,
            defaultPlaybackRate: Double(player?.defaultRate ?? 1),
            serverIdentifier: currentStore?.connection?.serverIdentifier,
            queuePosition: queue?.currentPosition,
            queueCount: queue?.totalCount
        )
    }

    private var nowPlayingStatus: PlexPlaybackStatus {
        guard let player else { return .idle }
        if hasReachedEnd {
            return .ended
        }
        if let playerItem = player.currentItem,
           let failure = playbackFailureMessage(player: player, item: playerItem) {
            return .failed(failure)
        }
        switch player.timeControlStatus {
        case .playing:
            return .playing
        case .waitingToPlayAtSpecifiedRate:
            return player.currentItem?.status == .readyToPlay ? .buffering : .preparing
        case .paused:
            return player.currentItem?.status == .readyToPlay ? .paused : .preparing
        @unknown default:
            return .preparing
        }
    }

    private var isPlaybackControlBusy: Bool {
        isReconfiguringMediaSelection
            || isNavigatingQueue
            || isMutatingQueue
            || isReplacingPlayback
            || rewindOnResumeTask != nil
            || isPreparingInitialPosition
    }

    private func applyAutoplay(_ autoplay: Bool, to player: AVPlayer) {
        // Only the completed initial seek may release pending resume playback.
        // Error recovery and audio interruptions must not start at zero first.
        if autoplay && !isPreparingInitialPosition {
            player.play()
        } else {
            player.pause()
        }
    }

    private func playbackRate(for player: AVPlayer) -> PlexPlaybackRate {
        PlexPlaybackRate(remoteCommandValue: player.defaultRate) ?? .normal
    }

    private func failPlayback(
        message: String,
        player: AVPlayer,
        request: TVPlexPlaybackRequest,
        store: TVAppStore
    ) {
        let time = playbackPosition(for: player)
        let playbackRate = playbackRate(for: player)
        let recovery = currentPlan.map {
            PlexPlaybackRecoveryRequest(
                plan: $0,
                videoQuality: selectedVideoQuality ?? store.activeVideoQuality,
                position: time
            )
        }
        stoppedTimelineSessionIdentifier = request.sessionIdentifier
        stoppedTimelineContinuing = nil
        resetPlayer()
        pendingRecovery = recovery.map { (request.id, $0, playbackRate) }
        canRetryPlayback = true
        errorMessage = message
        Task {
            _ = await reportPlayback(
                of: request,
                state: .stopped,
                time: time.isFinite ? time : 0,
                store: store
            )
        }
    }

    private func startTimelineReporting() {
        timelineTask?.cancel()
        timelineTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await reportTimelineIfNeeded()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func reportTimelineIfNeeded(
        force: Bool = false,
        time: TimeInterval? = nil,
        stateOverride: PlexTimelineState? = nil
    ) async {
        guard let player, let currentRequest, let currentStore else { return }
        let state = stateOverride ?? timelineState(for: player)
        let instant = ContinuousClock.now
        guard force || timelineCadence.shouldReport(state: state, at: instant) else { return }
        let position = pendingInitialSeekPosition ?? time ?? playbackPosition(for: player)
        let response = await reportPlayback(
            of: currentRequest,
            state: state,
            time: position,
            store: currentStore
        )
        guard self.player === player,
              self.currentRequest?.id == currentRequest.id else { return }
        if state != .stopped, let termination = response?.termination {
            terminatePlayback(termination)
            return
        }
        timelineCadence.record(state: state, at: instant)
    }

    private func reportStopped(
        continuing: Bool?,
        time: TimeInterval? = nil
    ) async -> Bool {
        guard let player, let currentRequest, let currentStore else { return false }
        let sessionIdentifier = currentRequest.sessionIdentifier
        let alreadyReported = stoppedTimelineSessionIdentifier == sessionIdentifier
            && stoppedTimelineContinuing == continuing
        player.pause()
        timelineTask?.cancel()
        timelineTask = nil
        if !alreadyReported {
            stoppedTimelineSessionIdentifier = sessionIdentifier
            stoppedTimelineContinuing = continuing
            let position = pendingInitialSeekPosition ?? time ?? playbackPosition(for: player)
            _ = await reportPlayback(
                of: currentRequest,
                state: .stopped,
                time: position.isFinite ? position : 0,
                continuing: continuing,
                store: currentStore
            )
        }
        return self.player === player
            && self.currentRequest?.sessionIdentifier == sessionIdentifier
    }

    private var completedPlaybackTime: TimeInterval {
        if let duration = currentRequest?.item.duration {
            return TimeInterval(max(duration, 0)) / 1_000
        }
        guard let position = player?.currentTime().seconds, position.isFinite else {
            return 0
        }
        return max(position, 0)
    }

    private func playbackPosition(for player: AVPlayer) -> TimeInterval {
        // AVPlayer reports zero while loading and seeking to the saved position.
        // That temporary value must not overwrite Plex progress or a retry offset.
        if let pendingInitialSeekPosition { return pendingInitialSeekPosition }
        let position = player.currentTime().seconds
        return position.isFinite ? max(position, 0) : 0
    }

    private func autoplayAfterReconfiguration(for player: AVPlayer) -> Bool {
        // Initial resume deliberately pauses AVPlayer until its seek completes.
        // Replacing that stream must preserve the requested playback intent.
        if isPreparingInitialPosition, let currentRequest {
            return currentRequest.autoplay
        }
        return player.timeControlStatus != .paused
    }

    private func reportPlayback(
        of request: TVPlexPlaybackRequest,
        state: PlexTimelineState,
        time: TimeInterval,
        continuing: Bool? = nil,
        store: TVAppStore
    ) async -> PlexTimelineResponse? {
        let time = time.isFinite ? max(time, 0) : 0
        let update = PlexTimelineUpdate(
            ratingKey: request.item.ratingKey,
            state: state,
            time: Int(time * 1_000),
            duration: request.item.duration ?? 0,
            sessionIdentifier: request.sessionIdentifier,
            playQueueItemID: request.queue?.currentItem.playQueueItemID
                ?? request.item.playQueueItemID,
            continuing: continuing
        )
        return await timelineReporter(for: store).report(update)
    }

    private func timelineReporter(for store: TVAppStore) -> PlexTimelineReportSequencer {
        if let timelineReporter {
            return timelineReporter
        }
        let reporter = PlexTimelineReportSequencer { [store] update in
            await store.reportPlayback(update)
        }
        timelineReporter = reporter
        return reporter
    }

    private func terminatePlayback(_ termination: PlexTimelineResponse.Termination) {
        resetPlayer()
        pendingRecovery = nil
        canRetryPlayback = false
        errorMessage = termination.message
    }

    private func timelineState(for player: AVPlayer) -> PlexTimelineState {
        switch player.timeControlStatus {
        case .paused:
            .paused
        case .waitingToPlayAtSpecifiedRate:
            .buffering
        case .playing:
            .playing
        @unknown default:
            .buffering
        }
    }

    private func updateMarkerAction(
        at position: TimeInterval,
        player: AVPlayer,
        playerItem: AVPlayerItem,
        request: TVPlexPlaybackRequest,
        store: TVAppStore
    ) {
        guard self.player === player,
              player.currentItem === playerItem,
              currentRequest?.id == request.id else {
            return
        }
        let duration = request.item.duration.map { TimeInterval($0) / 1_000 }
        let action = PlexPlaybackMarkerAction.active(
            in: request.item.markers,
            at: position,
            duration: duration
        )
        let preferences = store.playbackMarkerPreferences

        let manualAction = PlexPlaybackMarkerAction.manual(
            in: request.item.markers,
            at: position,
            duration: duration,
            preferences: preferences
        )
        if manualAction != activeMarkerAction {
            activeMarkerAction = manualAction
        }

        guard let automaticAction = automaticMarkerTransition.action(
            for: action,
            preferences: preferences
        ) else {
            return
        }

        let timeJumpToken = expectedTimeJumps.expect(target: automaticAction.targetTime)
        player.seek(
            to: CMTime(seconds: automaticAction.targetTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self, weak player, weak playerItem] completed in
            Task { @MainActor in
                guard let self else { return }
                guard let player,
                      let playerItem,
                      self.player === player,
                      player.currentItem === playerItem,
                      self.currentRequest?.id == request.id else {
                    self.expectedTimeJumps.cancel(timeJumpToken)
                    return
                }
                if completed {
                    await self.reportTimelineIfNeeded(
                        force: true,
                        time: automaticAction.targetTime
                    )
                } else {
                    self.expectedTimeJumps.cancel(timeJumpToken)
                    self.automaticMarkerTransition.retry(automaticAction)
                }
            }
        }
    }

    func playbackMarkerPreferencesDidChange(
        _ preferences: PlexPlaybackMarkerPreferences,
        store: TVAppStore
    ) {
        guard let player,
              let playerItem = player.currentItem,
              let currentRequest else {
            return
        }
        updateMarkerAction(
            at: player.currentTime().seconds,
            player: player,
            playerItem: playerItem,
            request: currentRequest,
            store: store
        )
    }

    private func metadata(for item: PlexMediaItem) -> [AVMetadataItem] {
        let presentation = PlexPlayerPlaybackInfoPresentation(item: item)
        var values = [
            metadataItem(identifier: .commonIdentifierTitle, value: presentation.title),
        ]
        if let hierarchyLine = presentation.hierarchyLine {
            values.append(metadataItem(
                identifier: .iTunesMetadataTrackSubTitle,
                value: hierarchyLine
            ))
        }
        if let summary = presentation.summary {
            values.append(metadataItem(identifier: .commonIdentifierDescription, value: summary))
        }
        if let contentRating = presentation.contentRating {
            values.append(metadataItem(
                identifier: .iTunesMetadataContentRating,
                value: contentRating
            ))
        }
        if let genre = presentation.genre {
            values.append(metadataItem(identifier: .quickTimeMetadataGenre, value: genre))
        }
        return values
    }

    private func navigationMarkerGroups(for item: PlexMediaItem) -> [AVNavigationMarkersGroup] {
        let chapters = PlexPlaybackChapter.chapters(
            from: item.chapters,
            mediaDurationMilliseconds: item.duration
        )
        return navigationMarkerGroups(for: chapters)
    }

    private func navigationMarkerGroups(
        for chapters: [PlexPlaybackChapter],
        artworkByChapterID: [String: Data] = [:]
    ) -> [AVNavigationMarkersGroup] {
        guard !chapters.isEmpty else { return [] }

        let markers = chapters.map { chapter in
            var metadata = [
                metadataItem(identifier: .commonIdentifierTitle, value: chapter.title)
            ]
            if let artwork = artworkByChapterID[chapter.id] {
                metadata.append(artworkMetadataItem(artwork))
            }
            return AVTimedMetadataGroup(
                items: metadata,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: chapter.startTime, preferredTimescale: 600),
                    duration: CMTime(seconds: chapter.duration, preferredTimescale: 600)
                )
            )
        }
        return [AVNavigationMarkersGroup(title: nil, timedNavigationMarkers: markers)]
    }

    private func interstitialTimeRanges(for item: PlexMediaItem) -> [AVInterstitialTimeRange] {
        PlexPlaybackInterstitial.commercials(
            in: item.markers,
            duration: item.durationSeconds
        )
        .map { interstitial in
            AVInterstitialTimeRange(
                timeRange: CMTimeRange(
                    start: CMTime(
                        seconds: interstitial.startTime,
                        preferredTimescale: 600
                    ),
                    duration: CMTime(
                        seconds: interstitial.duration,
                        preferredTimescale: 600
                    )
                )
            )
        }
    }

    private func metadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as? AVMetadataItem ?? item
    }

    private func artworkMetadataItem(_ data: Data) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierArtwork
        item.value = data as NSData
        item.extendedLanguageTag = "und"
        return item.copy() as? AVMetadataItem ?? item
    }
}

private enum TVPlaybackQueueDestination: Sendable {
    case adjacent(PlexPlaybackQueueDirection)
    case item(String)
}

private enum TVPlaybackQueueMutation: Sendable {
    case shuffled(Bool)
    case move(String, PlexPlayQueueItemMoveDirection)
    case remove(String)
}

private enum TVPlaybackQueueFailureRecovery: Sendable {
    case navigation(TVPlaybackQueueDestination)
    case mutation(TVPlaybackQueueMutation)
    case completion
}

private enum TVAudioInterruptionEvent: Sendable {
    case began
    case ended(systemAllowsResume: Bool)

    init?(notification: Notification) {
        guard let typeNumber = notification.userInfo?[
            AVAudioSessionInterruptionTypeKey
        ] as? NSNumber,
            let type = AVAudioSession.InterruptionType(
                rawValue: typeNumber.uintValue
            ) else {
            return nil
        }

        switch type {
        case .began:
            self = .began
        case .ended:
            let optionsNumber = notification.userInfo?[
                AVAudioSessionInterruptionOptionKey
            ] as? NSNumber
            let options = AVAudioSession.InterruptionOptions(
                rawValue: optionsNumber?.uintValue ?? 0
            )
            self = .ended(systemAllowsResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }
}

private extension AVAudioSession.RenderingMode {
    var plexLabel: String? {
        switch self {
        case .notApplicable:
            nil
        case .monoStereo:
            "Mono / Stereo"
        case .surround:
            "Surround"
        case .spatialAudio:
            "Spatial Audio"
        case .dolbyAudio:
            "Dolby Audio"
        case .dolbyAtmos:
            "Dolby Atmos"
        @unknown default:
            nil
        }
    }
}

private struct TVPostPlayOverlay: View {
    private enum FocusedAction: Hashable {
        case playNow
        case notNow
    }

    let item: PlexMediaItem
    let title: String
    let countdown: Int?
    let playNow: () -> Void
    let cancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @FocusState private var focusedAction: FocusedAction?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TVPlexArtwork(
                path: item.preferredBackdropPath,
                width: 1920,
                height: 1080,
                systemImage: item.type?.lowercased() == "track" ? "music.note" : "film"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.18), location: 0),
                        .init(color: .black.opacity(0.58), location: 0.52),
                        .init(color: .black.opacity(0.96), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.88), .black.opacity(0.28), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .accessibilityHidden(true)

            HStack(alignment: .bottom, spacing: 60) {
                VStack(alignment: .leading, spacing: 18) {
                    Label(
                        title.uppercased(),
                        systemImage: title == "Up Next"
                            ? "play.square.stack"
                            : "person.fill.checkmark"
                    )
                        .font(.headline.bold())
                        .tracking(2)
                        .foregroundStyle(TVTheme.plexGold)

                    if let context = item.contextTitle {
                        Text(context)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.76))
                    }

                    Text(item.title)
                        .font(.largeTitle.bold())
                        .lineLimit(2)

                    if !item.metadataLine.isEmpty {
                        Text(item.metadataLine)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    if let summary = item.summary?.nilIfBlank {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(3)
                    }

                    playbackStatus
                        .padding(.top, 6)

                    HStack(spacing: 24) {
                        Button("Play Now", systemImage: "play.fill", action: playNow)
                            .buttonStyle(.borderedProminent)
                            .tint(TVTheme.plexGold)
                            .focused($focusedAction, equals: .playNow)
                        Button("Not Now", role: .cancel, action: cancel)
                            .focused($focusedAction, equals: .notNow)
                    }
                    .defaultFocus($focusedAction, .playNow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TVPlexArtwork(
                    path: item.preferredBackdropPath,
                    width: 1120,
                    height: 630,
                    systemImage: item.type?.lowercased() == "track" ? "music.note" : "film"
                )
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .containerRelativeFrame(.horizontal, count: 3, spacing: 40)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)
            }
            .safeAreaPadding()
        }
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var playbackStatus: some View {
        if let countdown {
            Label("Playing automatically in \(countdown) seconds", systemImage: "timer")
                .contentTransition(.numericText(value: Double(countdown)))
                .animation(
                    PlexMotion.contentReplacementAnimation(
                        reduceMotion: accessibilityReduceMotion
                    ),
                    value: countdown
                )
        } else {
            Label("Select Play Now to continue watching", systemImage: "pause.circle.fill")
        }
    }
}
