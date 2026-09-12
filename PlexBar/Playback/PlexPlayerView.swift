import AVKit
import OSLog
import SwiftUI

private let plexPlayerLogger = Logger(
    subsystem: AppConstants.bundleIdentifier,
    category: "Player"
)

struct PlexPlaybackPresentation: Identifiable {
    let item: PlexMediaItem
    let plan: PlexPlaybackPlan
    let queue: PlexPlaybackQueue?
    let videoQuality: PlexVideoQuality
    let serverIdentifier: String?
    let queueSourcePreference: PlexPlaybackQueueSourcePreference?
    let offlinePackageID: UUID?

    init(
        item: PlexMediaItem,
        plan: PlexPlaybackPlan,
        queue: PlexPlaybackQueue?,
        videoQuality: PlexVideoQuality,
        serverIdentifier: String? = nil,
        queueSourcePreference: PlexPlaybackQueueSourcePreference? = nil,
        offlinePackageID: UUID? = nil
    ) {
        self.item = item
        self.plan = plan
        self.queue = queue
        self.videoQuality = videoQuality
        self.serverIdentifier = serverIdentifier
        self.queueSourcePreference = queueSourcePreference
        self.offlinePackageID = offlinePackageID
    }

    var id: String { plan.sessionIdentifier }
}

struct PlexPlayerItemMutationTicket: Equatable, Sendable {
    let ratingKey: String
    let sessionIdentifier: String

    init(presentation: PlexPlaybackPresentation) {
        ratingKey = presentation.item.ratingKey
        sessionIdentifier = presentation.plan.sessionIdentifier
    }

    func accepts(_ presentation: PlexPlaybackPresentation) -> Bool {
        presentation.item.ratingKey == ratingKey
            && presentation.plan.sessionIdentifier == sessionIdentifier
    }
}

enum PlexPlayerLibraryHandoffPolicy {
    static func canOpen(
        playbackServerIdentifier: String?,
        browserServerIdentifier: String?
    ) -> Bool {
        guard let playbackServerIdentifier = playbackServerIdentifier?.nilIfBlank,
              let browserServerIdentifier = browserServerIdentifier?.nilIfBlank else {
            return false
        }
        return playbackServerIdentifier == browserServerIdentifier
    }
}

enum PlexPlayerNavigationTitle {
    static let fallback = "Player"

    static func resolve(_ mediaTitle: String?) -> String {
        mediaTitle?.nilIfBlank ?? fallback
    }
}

@MainActor
@Observable
final class PlexPlayerPresentationLifecycle {
    private(set) var isFullScreenActive = false
    private(set) var isFullScreenTransitioning = false
    private(set) var isPictureInPictureActive = false

    var keepsPlaybackAliveWhenViewDisappears: Bool {
        isFullScreenActive || isPictureInPictureActive
    }

    func willEnterFullScreen() {
        isFullScreenActive = true
        isFullScreenTransitioning = true
    }

    func didEnterFullScreen() {
        isFullScreenTransitioning = false
    }

    func willExitFullScreen() {
        isFullScreenTransitioning = true
    }

    func didExitFullScreen() {
        isFullScreenActive = false
        isFullScreenTransitioning = false
    }

    func willStartPictureInPicture() {
        isPictureInPictureActive = true
    }

    func failedToStartPictureInPicture() {
        isPictureInPictureActive = false
    }

    func didStopPictureInPicture() {
        isPictureInPictureActive = false
    }
}

struct PlexPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.openWindow) private var openWindow
    @State private var session: PlexPlayerSessionModel
    @State private var presentationLifecycle: PlexPlayerPresentationLifecycle
    @State private var overlaySelection = PlexPlayerOverlaySelection()
    @State private var isPlaybackEndedOverlayDismissed = false
    private let coordinator: PlexPlayerCoordinator
    private let settingsStore: PlexSettingsStore

    init(
        presentation: PlexPlaybackPresentation,
        browserStore: PlexBrowserStore,
        settingsStore: PlexSettingsStore,
        coordinator: PlexPlayerCoordinator,
        downloadsStore: PlexDownloadsStore
    ) {
        self.coordinator = coordinator
        self.settingsStore = settingsStore
        _presentationLifecycle = State(initialValue: PlexPlayerPresentationLifecycle())
        _session = State(initialValue: coordinator.session(
            for: presentation,
            browserStore: browserStore,
            settingsStore: settingsStore,
            downloadsStore: downloadsStore
        ))
    }

    var body: some View {
        PlexPlayerStage {
            ZStack {
                PlexAVPlayerView(
                    player: session.engine.player,
                    playbackRate: session.engine.playbackRate,
                    audioOverlay: audioOverlay,
                    mediaSelection: session.mediaSelection,
                    videoQualitySelection: session.videoQualitySelection,
                    videoDynamicRange: settingsStore.videoDynamicRange,
                    videoScalingMode: settingsStore.videoScalingMode,
                    canChangeMediaSelection: session.canChangeMediaSelection,
                    nativeMediaSelectionGeneration: session.nativeMediaSelectionGeneration,
                    markerAction: session.activeMarkerAction,
                    presentationLifecycle: presentationLifecycle,
                    restorePlayerInterface: restorePlayerInterface,
                    onSelectPlaybackRate: session.selectPlaybackRate,
                    onSelectAudioStream: session.selectAudioStream,
                    onSelectSubtitleStream: session.selectSubtitleStream,
                    onSelectVideoQuality: session.selectVideoQuality,
                    onSelectVideoDynamicRange: selectVideoDynamicRange,
                    onSelectVideoScalingMode: selectVideoScalingMode,
                    onUpdateNativeMediaSelectionAvailability: session.updateNativeMediaSelectionAvailability,
                    onSkipMarker: session.skipActiveMarker
                )

                if session.showsVideoPreparationStage {
                    PlexVideoPreparationStage(
                        item: session.presentation.item,
                        serverURL: session.artworkServerURL,
                        token: session.artworkToken,
                        clientContext: session.artworkClientContext
                    )
                    .transition(.opacity)
                }

                if session.hasPostPlayPresentation,
                   session.engine.status == .ended,
                   !isPlaybackEndedOverlayDismissed {
                    PlexPlaybackEndedOverlay(
                        session: session,
                        dismiss: { isPlaybackEndedOverlayDismissed = true }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if let overlay = overlaySelection.selected {
                    Color.black.opacity(overlayStyle.backgroundScrimOpacity)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { overlaySelection.dismiss() }
                        .transition(.opacity)

                    PlexPlayerHUD(
                        title: overlay.label,
                        systemImage: overlay.systemImage,
                        dismiss: { overlaySelection.dismiss() }
                    ) {
                        switch overlay {
                        case .info:
                            PlexPlayerPlaybackInfoHUD(session: session)
                        case .upNext:
                            PlexUpNextHUD(session: session)
                        }
                    }
                    .padding(24)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
                }
            }
            .animation(
                accessibilityReduceMotion ? nil : .easeOut(duration: 0.2),
                value: session.showsVideoPreparationStage
            )
            .animation(
                accessibilityReduceMotion ? nil : .easeOut(duration: 0.2),
                value: session.hasPostPlayPresentation && !isPlaybackEndedOverlayDismissed
            )
            .animation(
                accessibilityReduceMotion ? nil : .snappy(duration: 0.22),
                value: overlaySelection.selected
            )
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
        .frame(minWidth: 760, minHeight: 500)
        .navigationTitle(PlexPlayerNavigationTitle.resolve(session.presentation.item.title))
        .focusedSceneValue(\.plexPlayerSurfaceIsFocused, true)
        .focusedSceneValue(
            \.plexPlayerInfoCommand,
            PlexFocusedCommandAction(
                title: overlaySelection.commandTitle(for: .info),
                perform: togglePlaybackInfoOverlay
            )
        )
        .focusedSceneValue(
            \.plexPlayerUpNextCommand,
            PlexFocusedCommandAction(
                title: overlaySelection.commandTitle(for: .upNext),
                perform: toggleUpNextOverlay
            )
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Back to Library", systemImage: "chevron.backward", action: closePlayer)
                    .help("Stop Playback and Return to Library")
                    .keyboardShortcut(presentationLifecycle.isFullScreenActive ? nil : .cancelAction)
            }

            ToolbarItem(placement: .automatic) {
                PlexPlaybackOptionsMenu(
                    session: session,
                    settingsStore: settingsStore
                )
            }

            ToolbarItem(placement: .automatic) {
                PlexPlaybackRoutePicker(player: session.engine.player)
                    .frame(width: 28, height: 28)
                    .help("Choose Playback Destination")
            }

            ToolbarItem(placement: .automatic) {
                Button("Playback Info", systemImage: "info.circle", action: togglePlaybackInfoOverlay)
                    .help(
                        overlaySelection.selected == .info
                            ? "Hide Playback Info"
                            : "Show Playback Info"
                    )
                    .accessibilityValue(
                        overlaySelection.selected == .info ? "Shown" : "Hidden"
                    )
            }

            ToolbarItem(placement: .automatic) {
                Button("Up Next", systemImage: "list.bullet", action: toggleUpNextOverlay)
                    .help(
                        overlaySelection.selected == .upNext
                            ? "Hide Up Next"
                            : "Show Up Next"
                    )
                    .accessibilityValue(
                        overlaySelection.selected == .upNext ? "Shown" : "Hidden"
                    )
            }
        }
        .task {
            await session.start()
        }
        .onChange(of: session.engine.status, initial: true) {
            session.playbackStatusDidChange()
        }
        .onChange(of: session.engine.metricFacts) {
            session.playbackMetricsDidChange()
        }
        .onChange(of: settingsStore.qualitySuggestionsEnabled) {
            session.qualitySuggestionSettingsDidChange()
        }
        .onChange(of: session.engine.position, initial: true) {
            session.playbackPositionDidChange()
        }
        .onChange(of: settingsStore.playbackMarkerPreferences) {
            session.playbackMarkerPreferencesDidChange()
        }
        .onChange(of: session.engine.unexpectedTimeJumpRevision) {
            session.playbackTimeDidJump()
        }
        .onChange(of: session.hasPostPlayPresentation, initial: true) {
            if !session.hasPostPlayPresentation {
                isPlaybackEndedOverlayDismissed = false
            }
        }
        .onChange(of: session.presentation.item.ratingKey) {
            overlaySelection.dismiss()
            isPlaybackEndedOverlayDismissed = false
        }
        .onDisappear {
            handleViewDisappearance()
        }
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        session.errorMessage = nil
                    }
                }
            )
        ) {
            if session.canRetryPlayback {
                Button("Retry") {
                    session.retryPlayback()
                }
            }
            Button("Close", role: .cancel, action: closePlayer)
        } message: {
            Text(session.errorMessage ?? "Unknown playback error.")
        }
    }

    private func selectVideoDynamicRange(_ dynamicRange: PlexVideoDisplayDynamicRange) {
        guard settingsStore.videoDynamicRange != dynamicRange else {
            return
        }
        settingsStore.videoDynamicRange = dynamicRange
    }

    private func selectVideoScalingMode(_ scalingMode: PlexVideoScalingMode) {
        guard settingsStore.videoScalingMode != scalingMode else {
            return
        }
        settingsStore.videoScalingMode = scalingMode
    }

    private func togglePlaybackInfoOverlay() {
        overlaySelection.toggle(.info)
    }

    private func toggleUpNextOverlay() {
        overlaySelection.toggle(.upNext)
    }

    private var audioOverlay: PlexAudioPlayerOverlay? {
        guard let presentation = PlexAudioPlaybackPresentation(
            item: session.presentation.item,
            source: session.presentation.plan.source
        ) else {
            return nil
        }

        return PlexAudioPlayerOverlay(
            presentation: presentation,
            serverURL: session.artworkServerURL,
            token: session.artworkToken,
            clientContext: session.artworkClientContext
        )
    }

    private func closePlayer() {
        coordinator.close(session)
    }

    private func handleViewDisappearance() {
        guard coordinator.isActive(session),
              !presentationLifecycle.keepsPlaybackAliveWhenViewDisappears else {
            return
        }

        closePlayer()
    }

    private func restorePlayerInterface(completion: @escaping (Bool) -> Void) {
        openWindow(id: PlexMainNavigationStore.windowID)
        completion(true)
    }

    private var overlayStyle: PlexPlayerOverlayStyle {
        PlexPlayerOverlayStyle(contrast: colorSchemeContrast)
    }
}

struct PlexPlayerOverlayStyle: Equatable {
    let backgroundScrimOpacity: Double

    init(contrast: ColorSchemeContrast) {
        backgroundScrimOpacity = contrast == .increased ? 0.24 : 0.14
    }
}

enum PlexPlayerOverlay: Equatable, Sendable {
    case info
    case upNext
}

struct PlexPlayerOverlaySelection: Equatable, Sendable {
    private(set) var selected: PlexPlayerOverlay?

    var isPresented: Bool {
        selected != nil
    }

    func commandTitle(for overlay: PlexPlayerOverlay) -> String {
        selected == overlay ? "Hide \(overlay.label)" : "Show \(overlay.label)"
    }

    mutating func toggle(_ overlay: PlexPlayerOverlay) {
        selected = selected == overlay ? nil : overlay
    }

    mutating func dismiss() {
        selected = nil
    }

    mutating func present(_ overlay: PlexPlayerOverlay) {
        selected = overlay
    }
}

extension PlexPlayerOverlay {
    var label: String {
        switch self {
        case .info: "Playback Info"
        case .upNext: "Up Next"
        }
    }

    var systemImage: String {
        switch self {
        case .info: "info.circle"
        case .upNext: "list.bullet"
        }
    }
}

struct PlexPlayerStage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }
}

enum PlexNativePlayerSizing {
    static func exactSize(for proposal: ProposedViewSize) -> CGSize? {
        guard let width = proposal.width,
              let height = proposal.height,
              width.isFinite,
              height.isFinite,
              width > 0,
              height > 0 else {
            return nil
        }

        return CGSize(width: width, height: height)
    }
}

@MainActor
enum PlexPlaybackRoutePickerConfiguration {
    static func apply(
        to routePickerView: AVRoutePickerView,
        player: AVPlayer
    ) {
        if routePickerView.player !== player {
            routePickerView.player = player
        }
    }
}

private struct PlexPlaybackOptionsMenu: View {
    let session: PlexPlayerSessionModel
    let settingsStore: PlexSettingsStore

    var body: some View {
        Menu {
            if session.videoQualitySelection.isVideo {
                videoQualityMenu
                videoDynamicRangeMenu
                videoScalingMenu
                Divider()
            }

            playbackSpeedMenu

            if session.serverManagedMediaSelection.hasChoices {
                Divider()
                serverManagedMediaSelectionMenus
            }
        } label: {
            Label("Playback Options", systemImage: "gearshape")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Choose Playback Options")
        .accessibilityLabel("Playback Options")
    }

    private var videoQualityMenu: some View {
        Menu("Video Quality") {
            ForEach(PlexVideoQuality.allCases) { quality in
                Button {
                    session.selectVideoQuality(quality)
                } label: {
                    if session.videoQualitySelection.selectedQuality == quality {
                        Label(quality.label, systemImage: "checkmark")
                    } else {
                        Text(quality.label)
                    }
                }
                .disabled(!session.videoQualitySelection.canSelect(quality))
            }
        }
    }

    private var videoDynamicRangeMenu: some View {
        Menu("Video Dynamic Range") {
            ForEach(PlexVideoDisplayDynamicRange.allCases) { dynamicRange in
                Button {
                    settingsStore.videoDynamicRange = dynamicRange
                } label: {
                    if settingsStore.videoDynamicRange == dynamicRange {
                        Label(dynamicRange.label, systemImage: "checkmark")
                    } else {
                        Text(dynamicRange.label)
                    }
                }
            }
        }
    }

    private var videoScalingMenu: some View {
        Menu("Video Scaling") {
            ForEach(PlexVideoScalingMode.allCases) { scalingMode in
                Button {
                    settingsStore.videoScalingMode = scalingMode
                } label: {
                    if settingsStore.videoScalingMode == scalingMode {
                        Label(scalingMode.label, systemImage: "checkmark")
                    } else {
                        Text(scalingMode.label)
                    }
                }
            }
        }
    }

    private var playbackSpeedMenu: some View {
        Menu("Playback Speed") {
            ForEach(PlexPlaybackRate.allCases) { playbackRate in
                Button {
                    session.selectPlaybackRate(playbackRate)
                } label: {
                    if session.engine.playbackRate == playbackRate {
                        Label(playbackRate.label, systemImage: "checkmark")
                    } else {
                        Text(playbackRate.label)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var serverManagedMediaSelectionMenus: some View {
        let selection = session.serverManagedMediaSelection

        if !selection.audioOptions.isEmpty {
            Menu("Audio Track") {
                ForEach(selection.audioOptions) { option in
                    Button {
                        session.selectAudioStream(option.id)
                    } label: {
                        if option.isSelected {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }
            .disabled(!session.canChangeMediaSelection)
        }

        if !selection.subtitleOptions.isEmpty {
            Menu("Subtitles") {
                Button {
                    session.selectSubtitleStream(nil)
                } label: {
                    if selection.subtitleOptions.contains(where: \.isSelected) {
                        Text("Off")
                    } else {
                        Label("Off", systemImage: "checkmark")
                    }
                }

                ForEach(selection.subtitleOptions) { option in
                    Button {
                        session.selectSubtitleStream(option.id)
                    } label: {
                        if option.isSelected {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }
            .disabled(!session.canChangeMediaSelection)
        }
    }
}

private struct PlexPlaybackRoutePicker: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        PlexPlaybackRoutePickerConfiguration.apply(
            to: routePickerView,
            player: player
        )
        return routePickerView
    }

    func updateNSView(_ routePickerView: AVRoutePickerView, context: Context) {
        PlexPlaybackRoutePickerConfiguration.apply(
            to: routePickerView,
            player: player
        )
    }
}

private struct PlexAVPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let playbackRate: PlexPlaybackRate
    let audioOverlay: PlexAudioPlayerOverlay?
    let mediaSelection: PlexPlaybackMediaSelection
    let videoQualitySelection: PlexVideoQualitySelection
    let videoDynamicRange: PlexVideoDisplayDynamicRange
    let videoScalingMode: PlexVideoScalingMode
    let canChangeMediaSelection: Bool
    let nativeMediaSelectionGeneration: UInt
    let markerAction: PlexPlaybackMarkerAction?
    let presentationLifecycle: PlexPlayerPresentationLifecycle
    let restorePlayerInterface: (@escaping (Bool) -> Void) -> Void
    let onSelectPlaybackRate: (PlexPlaybackRate) -> Void
    let onSelectAudioStream: (Int) -> Void
    let onSelectSubtitleStream: (Int?) -> Void
    let onSelectVideoQuality: (PlexVideoQuality) -> Void
    let onSelectVideoDynamicRange: (PlexVideoDisplayDynamicRange) -> Void
    let onSelectVideoScalingMode: (PlexVideoScalingMode) -> Void
    let onUpdateNativeMediaSelectionAvailability: (
        PlexNativeMediaSelectionAvailability,
        UInt
    ) -> Void
    let onSkipMarker: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            presentationLifecycle: presentationLifecycle,
            nativeMediaSelectionGeneration: nativeMediaSelectionGeneration,
            restorePlayerInterface: restorePlayerInterface,
            onSelectPlaybackRate: onSelectPlaybackRate,
            onSelectAudioStream: onSelectAudioStream,
            onSelectSubtitleStream: onSelectSubtitleStream,
            onSelectVideoQuality: onSelectVideoQuality,
            onSelectVideoDynamicRange: onSelectVideoDynamicRange,
            onSelectVideoScalingMode: onSelectVideoScalingMode,
            onUpdateNativeMediaSelectionAvailability: onUpdateNativeMediaSelectionAvailability,
            onSkipMarker: onSkipMarker
        )
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        context.coordinator.updatePlaybackSpeeds(
            in: playerView,
            playbackRate: playbackRate,
            onSelectPlaybackRate: onSelectPlaybackRate
        )
        updatePresentationStyle(of: playerView)
        PlexNativeVideoScalingConfiguration.apply(
            to: playerView,
            scalingMode: videoScalingMode
        )
        playerView.preferredDisplayDynamicRange = videoDynamicRange.avDisplayDynamicRange
        playerView.updatesNowPlayingInfoCenter = false
        playerView.delegate = context.coordinator
        context.coordinator.installFullScreenKeyboardHandler(on: playerView)
        playerView.pictureInPictureDelegate = context.coordinator
        context.coordinator.updateAudioStage(in: playerView, overlay: audioOverlay)
        context.coordinator.installMarkerOverlay(in: playerView)
        context.coordinator.update(
            mediaSelection: mediaSelection,
            videoQualitySelection: videoQualitySelection,
            videoDynamicRange: videoDynamicRange,
            videoScalingMode: videoScalingMode,
            canChangeMediaSelection: canChangeMediaSelection,
            nativeMediaSelectionGeneration: nativeMediaSelectionGeneration,
            markerAction: markerAction,
            playerView: playerView,
            restorePlayerInterface: restorePlayerInterface,
            onSelectAudioStream: onSelectAudioStream,
            onSelectSubtitleStream: onSelectSubtitleStream,
            onSelectVideoQuality: onSelectVideoQuality,
            onSelectVideoDynamicRange: onSelectVideoDynamicRange,
            onSelectVideoScalingMode: onSelectVideoScalingMode,
            onUpdateNativeMediaSelectionAvailability: onUpdateNativeMediaSelectionAvailability,
            onSkipMarker: onSkipMarker
        )
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        if playerView.player !== player {
            playerView.player = player
        }
        context.coordinator.updatePlaybackSpeeds(
            in: playerView,
            playbackRate: playbackRate,
            onSelectPlaybackRate: onSelectPlaybackRate
        )
        updatePresentationStyle(of: playerView)
        PlexNativeVideoScalingConfiguration.apply(
            to: playerView,
            scalingMode: videoScalingMode
        )
        let preferredDisplayDynamicRange = videoDynamicRange.avDisplayDynamicRange
        if playerView.preferredDisplayDynamicRange != preferredDisplayDynamicRange {
            playerView.preferredDisplayDynamicRange = preferredDisplayDynamicRange
        }
        context.coordinator.updateAudioStage(in: playerView, overlay: audioOverlay)
        context.coordinator.update(
            mediaSelection: mediaSelection,
            videoQualitySelection: videoQualitySelection,
            videoDynamicRange: videoDynamicRange,
            videoScalingMode: videoScalingMode,
            canChangeMediaSelection: canChangeMediaSelection,
            nativeMediaSelectionGeneration: nativeMediaSelectionGeneration,
            markerAction: markerAction,
            playerView: playerView,
            restorePlayerInterface: restorePlayerInterface,
            onSelectAudioStream: onSelectAudioStream,
            onSelectSubtitleStream: onSelectSubtitleStream,
            onSelectVideoQuality: onSelectVideoQuality,
            onSelectVideoDynamicRange: onSelectVideoDynamicRange,
            onSelectVideoScalingMode: onSelectVideoScalingMode,
            onUpdateNativeMediaSelectionAvailability: onUpdateNativeMediaSelectionAvailability,
            onSkipMarker: onSkipMarker
        )
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: Coordinator) {
        coordinator.stopFullScreenKeyboardHandler()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: AVPlayerView,
        context: Context
    ) -> CGSize? {
        PlexNativePlayerSizing.exactSize(for: proposal)
    }

    private func updatePresentationStyle(of playerView: AVPlayerView) {
        let isAudio = audioOverlay != nil
        let controlsStyle: AVPlayerViewControlsStyle = isAudio ? .inline : .floating
        if playerView.controlsStyle != controlsStyle {
            playerView.controlsStyle = controlsStyle
        }
        playerView.showsFullScreenToggleButton = !isAudio
        playerView.allowsPictureInPicturePlayback = !isAudio
    }

    @MainActor
    final class Coordinator: NSObject, @MainActor AVPlayerViewDelegate, @MainActor AVPlayerViewPictureInPictureDelegate {
        private let presentationLifecycle: PlexPlayerPresentationLifecycle
        private var fullScreenKeyboardHandler: PlexVideoFullScreenKeyboardHandler?
        private var restorePlayerInterface: (@escaping (Bool) -> Void) -> Void
        private var onSelectPlaybackRate: (PlexPlaybackRate) -> Void
        private var mediaSelection: PlexPlaybackMediaSelection?
        private var videoQualitySelection: PlexVideoQualitySelection?
        private var videoDynamicRange: PlexVideoDisplayDynamicRange?
        private var videoScalingMode: PlexVideoScalingMode?
        private var canChangeMediaSelection = false
        private var nativeMediaSelectionGeneration: UInt
        private var markerAction: PlexPlaybackMarkerAction?
        private var inspectedItemIdentifier: ObjectIdentifier?
        private var nativeAvailability: PlexNativeMediaSelectionAvailability?
        private var inspectionTask: Task<Void, Never>?
        private var playbackRateObservation: NSKeyValueObservation?
        private weak var observedPlaybackRatePlayer: AVPlayer?
        private var playbackRateObservationEpoch = PlexNativePlaybackRateObservationEpoch()
        private let audioStageHost = PlexAudioPlayerStageHost()
        private var markerHostingView: NSHostingView<PlexSkipMarkerControl>?
        private var onSelectAudioStream: (Int) -> Void
        private var onSelectSubtitleStream: (Int?) -> Void
        private var onSelectVideoQuality: (PlexVideoQuality) -> Void
        private var onSelectVideoDynamicRange: (PlexVideoDisplayDynamicRange) -> Void
        private var onSelectVideoScalingMode: (PlexVideoScalingMode) -> Void
        private var onUpdateNativeMediaSelectionAvailability: (
            PlexNativeMediaSelectionAvailability,
            UInt
        ) -> Void
        private var onSkipMarker: () -> Void

        init(
            presentationLifecycle: PlexPlayerPresentationLifecycle,
            nativeMediaSelectionGeneration: UInt,
            restorePlayerInterface: @escaping (@escaping (Bool) -> Void) -> Void,
            onSelectPlaybackRate: @escaping (PlexPlaybackRate) -> Void,
            onSelectAudioStream: @escaping (Int) -> Void,
            onSelectSubtitleStream: @escaping (Int?) -> Void,
            onSelectVideoQuality: @escaping (PlexVideoQuality) -> Void,
            onSelectVideoDynamicRange: @escaping (PlexVideoDisplayDynamicRange) -> Void,
            onSelectVideoScalingMode: @escaping (PlexVideoScalingMode) -> Void,
            onUpdateNativeMediaSelectionAvailability: @escaping (
                PlexNativeMediaSelectionAvailability,
                UInt
            ) -> Void,
            onSkipMarker: @escaping () -> Void
        ) {
            self.presentationLifecycle = presentationLifecycle
            self.nativeMediaSelectionGeneration = nativeMediaSelectionGeneration
            self.restorePlayerInterface = restorePlayerInterface
            self.onSelectPlaybackRate = onSelectPlaybackRate
            self.onSelectAudioStream = onSelectAudioStream
            self.onSelectSubtitleStream = onSelectSubtitleStream
            self.onSelectVideoQuality = onSelectVideoQuality
            self.onSelectVideoDynamicRange = onSelectVideoDynamicRange
            self.onSelectVideoScalingMode = onSelectVideoScalingMode
            self.onUpdateNativeMediaSelectionAvailability = onUpdateNativeMediaSelectionAvailability
            self.onSkipMarker = onSkipMarker
        }

        func updatePlaybackSpeeds(
            in playerView: AVPlayerView,
            playbackRate: PlexPlaybackRate,
            onSelectPlaybackRate: @escaping (PlexPlaybackRate) -> Void
        ) {
            self.onSelectPlaybackRate = onSelectPlaybackRate
            PlexNativePlaybackSpeedConfiguration.apply(
                to: playerView,
                playbackRate: playbackRate
            )

            guard let player = playerView.player else {
                playbackRateObservation?.invalidate()
                playbackRateObservation = nil
                observedPlaybackRatePlayer = nil
                playbackRateObservationEpoch.invalidate()
                return
            }

            guard !playbackRateObservationEpoch.isCurrent(player: player) else {
                return
            }

            playbackRateObservation?.invalidate()
            observedPlaybackRatePlayer = player
            let ticket = playbackRateObservationEpoch.begin(player: player)
            playbackRateObservation = player.observe(
                \.defaultRate,
                options: [.new]
            ) { [weak self] _, change in
                guard let rawValue = change.newValue else {
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self,
                          let observedPlaybackRatePlayer,
                          let playbackRate = playbackRateObservationEpoch.playbackRate(
                            for: rawValue,
                            ticket: ticket,
                            player: observedPlaybackRatePlayer
                          ) else {
                        return
                    }
                    self.onSelectPlaybackRate(playbackRate)
                }
            }
        }

        func updateAudioStage(in playerView: AVPlayerView, overlay: PlexAudioPlayerOverlay?) {
            audioStageHost.update(
                in: playerView.contentOverlayView,
                overlay: overlay
            )
        }

        func installMarkerOverlay(in playerView: AVPlayerView) {
            guard markerHostingView == nil, let overlayView = playerView.contentOverlayView else {
                return
            }

            let hostingView = NSHostingView(
                rootView: PlexSkipMarkerControl(action: nil, perform: onSkipMarker)
            )
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            overlayView.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.trailingAnchor.constraint(
                    equalTo: overlayView.layoutMarginsGuide.trailingAnchor
                ),
                hostingView.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: -84),
            ])
            markerHostingView = hostingView
        }

        func update(
            mediaSelection: PlexPlaybackMediaSelection,
            videoQualitySelection: PlexVideoQualitySelection,
            videoDynamicRange: PlexVideoDisplayDynamicRange,
            videoScalingMode: PlexVideoScalingMode,
            canChangeMediaSelection: Bool,
            nativeMediaSelectionGeneration: UInt,
            markerAction: PlexPlaybackMarkerAction?,
            playerView: AVPlayerView,
            restorePlayerInterface: @escaping (@escaping (Bool) -> Void) -> Void,
            onSelectAudioStream: @escaping (Int) -> Void,
            onSelectSubtitleStream: @escaping (Int?) -> Void,
            onSelectVideoQuality: @escaping (PlexVideoQuality) -> Void,
            onSelectVideoDynamicRange: @escaping (PlexVideoDisplayDynamicRange) -> Void,
            onSelectVideoScalingMode: @escaping (PlexVideoScalingMode) -> Void,
            onUpdateNativeMediaSelectionAvailability: @escaping (
                PlexNativeMediaSelectionAvailability,
                UInt
            ) -> Void,
            onSkipMarker: @escaping () -> Void
        ) {
            self.restorePlayerInterface = restorePlayerInterface
            self.onSelectAudioStream = onSelectAudioStream
            self.onSelectSubtitleStream = onSelectSubtitleStream
            self.onSelectVideoQuality = onSelectVideoQuality
            self.onSelectVideoDynamicRange = onSelectVideoDynamicRange
            self.onSelectVideoScalingMode = onSelectVideoScalingMode
            self.onUpdateNativeMediaSelectionAvailability = onUpdateNativeMediaSelectionAvailability
            self.onSkipMarker = onSkipMarker
            let generationChanged = self.nativeMediaSelectionGeneration
                != nativeMediaSelectionGeneration
            self.nativeMediaSelectionGeneration = nativeMediaSelectionGeneration
            if generationChanged {
                nativeAvailability = nil
                inspectionTask?.cancel()
                inspectionTask = nil
                playerView.actionPopUpButtonMenu = nil
            }
            let selectionChanged = self.mediaSelection != mediaSelection
            let qualityChanged = self.videoQualitySelection != videoQualitySelection
            let dynamicRangeChanged = self.videoDynamicRange != videoDynamicRange
            let scalingModeChanged = self.videoScalingMode != videoScalingMode
            let mediaAvailabilityChanged = self.canChangeMediaSelection != canChangeMediaSelection
            let markerChanged = self.markerAction != markerAction
            self.mediaSelection = mediaSelection
            self.videoQualitySelection = videoQualitySelection
            self.videoDynamicRange = videoDynamicRange
            self.videoScalingMode = videoScalingMode
            self.canChangeMediaSelection = canChangeMediaSelection
            self.markerAction = markerAction
            if markerChanged {
                markerHostingView?.rootView = PlexSkipMarkerControl(
                    action: markerAction,
                    perform: onSkipMarker
                )
            }

            guard let item = playerView.player?.currentItem else {
                inspectedItemIdentifier = nil
                nativeAvailability = nil
                inspectionTask?.cancel()
                inspectionTask = nil
                playerView.actionPopUpButtonMenu = nil
                return
            }

            let itemIdentifier = ObjectIdentifier(item)
            if generationChanged, inspectedItemIdentifier == itemIdentifier {
                return
            }
            if inspectedItemIdentifier != itemIdentifier {
                inspectedItemIdentifier = itemIdentifier
                nativeAvailability = nil
                inspectionTask?.cancel()
                playerView.actionPopUpButtonMenu = nil
                inspectNativeOptions(for: item, playerView: playerView)
                return
            }

            if selectionChanged || qualityChanged || dynamicRangeChanged || scalingModeChanged
                || mediaAvailabilityChanged || markerChanged,
               let nativeAvailability {
                playerView.actionPopUpButtonMenu = makeActionMenu(
                    for: mediaSelection,
                    videoQualitySelection: videoQualitySelection,
                    videoDynamicRange: videoDynamicRange,
                    videoScalingMode: videoScalingMode,
                    nativeAvailability: nativeAvailability,
                    markerAction: markerAction
                )
            }
        }

        func installFullScreenKeyboardHandler(on playerView: AVPlayerView) {
            fullScreenKeyboardHandler = PlexVideoFullScreenKeyboardHandler(
                playerView: playerView,
                lifecycle: presentationLifecycle
            )
            fullScreenKeyboardHandler?.start()
        }

        func stopFullScreenKeyboardHandler() {
            fullScreenKeyboardHandler?.stop()
            fullScreenKeyboardHandler = nil
        }

        func playerViewWillEnterFullScreen(_ playerView: AVPlayerView) {
            presentationLifecycle.willEnterFullScreen()
        }

        func playerViewDidEnterFullScreen(_ playerView: AVPlayerView) {
            presentationLifecycle.didEnterFullScreen()
        }

        func playerViewWillExitFullScreen(_ playerView: AVPlayerView) {
            presentationLifecycle.willExitFullScreen()
        }

        func playerViewDidExitFullScreen(_ playerView: AVPlayerView) {
            presentationLifecycle.didExitFullScreen()
        }

        func playerView(
            _ playerView: AVPlayerView,
            restoreUserInterfaceForFullScreenExitWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            restorePlayerInterface(completionHandler)
        }

        func playerViewWillStartPicture(inPicture playerView: AVPlayerView) {
            presentationLifecycle.willStartPictureInPicture()
        }

        func playerView(
            _ playerView: AVPlayerView,
            failedToStartPictureInPictureWithError error: any Error
        ) {
            presentationLifecycle.failedToStartPictureInPicture()
        }

        func playerViewDidStopPicture(inPicture playerView: AVPlayerView) {
            presentationLifecycle.didStopPictureInPicture()
        }

        func playerView(
            _ playerView: AVPlayerView,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            restorePlayerInterface(completionHandler)
        }

        private func inspectNativeOptions(for item: AVPlayerItem, playerView: AVPlayerView) {
            let inspectionGeneration = nativeMediaSelectionGeneration
            inspectionTask = Task { @MainActor [weak self, weak item, weak playerView] in
                guard let self, let item, let playerView else {
                    return
                }

                guard let availability = try? await PlexNativeMediaInspector
                    .mediaSelectionAvailability(asset: item.asset) else {
                    return
                }

                guard !Task.isCancelled,
                      inspectedItemIdentifier == ObjectIdentifier(item),
                      nativeMediaSelectionGeneration == inspectionGeneration,
                      let mediaSelection,
                      let videoQualitySelection,
                      let videoDynamicRange,
                      let videoScalingMode else {
                    return
                }
                nativeAvailability = availability
                onUpdateNativeMediaSelectionAvailability(availability, inspectionGeneration)
                playerView.actionPopUpButtonMenu = makeActionMenu(
                    for: mediaSelection,
                    videoQualitySelection: videoQualitySelection,
                    videoDynamicRange: videoDynamicRange,
                    videoScalingMode: videoScalingMode,
                    nativeAvailability: availability,
                    markerAction: markerAction
                )
            }
        }

        private func makeActionMenu(
            for selection: PlexPlaybackMediaSelection,
            videoQualitySelection: PlexVideoQualitySelection,
            videoDynamicRange: PlexVideoDisplayDynamicRange,
            videoScalingMode: PlexVideoScalingMode,
            nativeAvailability: PlexNativeMediaSelectionAvailability,
            markerAction: PlexPlaybackMarkerAction?
        ) -> NSMenu? {
            let includesVideoQuality = videoQualitySelection.isVideo
            let serverManagedSelection = PlexServerManagedMediaSelection(
                selection: selection,
                nativeAvailability: nativeAvailability
            )
            let includesAudio = !serverManagedSelection.audioOptions.isEmpty
            let includesSubtitles = !serverManagedSelection.subtitleOptions.isEmpty
            guard markerAction != nil || includesVideoQuality || includesAudio || includesSubtitles else {
                return nil
            }

            let menu = NSMenu(title: "Playback Options")
            if let markerAction {
                let item = NSMenuItem(
                    title: markerAction.label,
                    action: #selector(skipMarker),
                    keyEquivalent: ""
                )
                item.target = self
                item.image = NSImage(
                    systemSymbolName: "forward.end.fill",
                    accessibilityDescription: nil
                )
                menu.addItem(item)
                if includesVideoQuality || includesAudio || includesSubtitles {
                    menu.addItem(.separator())
                }
            }
            if includesVideoQuality {
                let item = NSMenuItem(title: "Video Quality", action: nil, keyEquivalent: "")
                item.submenu = videoQualityMenu(selection: videoQualitySelection)
                menu.addItem(item)
            }
            if videoQualitySelection.isVideo {
                let item = NSMenuItem(title: "Video Dynamic Range", action: nil, keyEquivalent: "")
                item.submenu = videoDynamicRangeMenu(selection: videoDynamicRange)
                menu.addItem(item)

                let scalingItem = NSMenuItem(
                    title: "Video Scaling",
                    action: nil,
                    keyEquivalent: ""
                )
                scalingItem.submenu = videoScalingMenu(selection: videoScalingMode)
                menu.addItem(scalingItem)
            }
            if includesAudio {
                let item = NSMenuItem(title: "Audio", action: nil, keyEquivalent: "")
                item.submenu = audioMenu(options: serverManagedSelection.audioOptions)
                menu.addItem(item)
            }
            if includesSubtitles {
                let item = NSMenuItem(title: "Subtitles", action: nil, keyEquivalent: "")
                item.submenu = subtitleMenu(options: serverManagedSelection.subtitleOptions)
                menu.addItem(item)
            }
            return menu
        }

        private func audioMenu(options: [PlexMediaSelectionOption]) -> NSMenu {
            let menu = NSMenu(title: "Audio")
            for option in options {
                let item = NSMenuItem(
                    title: option.title,
                    action: #selector(selectAudioStream(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = option.id
                item.state = option.isSelected ? .on : .off
                item.isEnabled = canChangeMediaSelection
                menu.addItem(item)
            }
            return menu
        }

        private func subtitleMenu(options: [PlexMediaSelectionOption]) -> NSMenu {
            let menu = NSMenu(title: "Subtitles")
            let offItem = NSMenuItem(
                title: "Off",
                action: #selector(selectSubtitleStream(_:)),
                keyEquivalent: ""
            )
            offItem.target = self
            offItem.representedObject = 0
            offItem.state = options.contains(where: \.isSelected) ? .off : .on
            offItem.isEnabled = canChangeMediaSelection
            menu.addItem(offItem)
            menu.addItem(.separator())

            for option in options {
                let item = NSMenuItem(
                    title: option.title,
                    action: #selector(selectSubtitleStream(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = option.id
                item.state = option.isSelected ? .on : .off
                item.isEnabled = canChangeMediaSelection
                menu.addItem(item)
            }
            return menu
        }

        private func videoQualityMenu(selection: PlexVideoQualitySelection) -> NSMenu {
            let menu = NSMenu(title: "Video Quality")
            for quality in PlexVideoQuality.allCases {
                let item = NSMenuItem(
                    title: quality.label,
                    action: #selector(selectVideoQuality(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = quality.rawValue
                item.state = quality == selection.selectedQuality ? .on : .off
                item.isEnabled = selection.canSelect(quality)
                menu.addItem(item)
            }
            return menu
        }

        private func videoDynamicRangeMenu(selection: PlexVideoDisplayDynamicRange) -> NSMenu {
            let menu = NSMenu(title: "Video Dynamic Range")
            for dynamicRange in PlexVideoDisplayDynamicRange.allCases {
                let item = NSMenuItem(
                    title: dynamicRange.label,
                    action: #selector(selectVideoDynamicRange(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = dynamicRange.rawValue
                item.state = dynamicRange == selection ? .on : .off
                menu.addItem(item)
            }
            return menu
        }

        private func videoScalingMenu(selection: PlexVideoScalingMode) -> NSMenu {
            let menu = NSMenu(title: "Video Scaling")
            for scalingMode in PlexVideoScalingMode.allCases {
                let item = NSMenuItem(
                    title: scalingMode.label,
                    action: #selector(selectVideoScalingMode(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = scalingMode.rawValue
                item.state = scalingMode == selection ? .on : .off
                menu.addItem(item)
            }
            return menu
        }

        @objc private func selectAudioStream(_ sender: NSMenuItem) {
            guard let streamID = sender.representedObject as? Int else {
                return
            }
            onSelectAudioStream(streamID)
        }

        @objc private func selectSubtitleStream(_ sender: NSMenuItem) {
            guard let streamID = sender.representedObject as? Int else {
                return
            }
            onSelectSubtitleStream(streamID == 0 ? nil : streamID)
        }

        @objc private func selectVideoQuality(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let quality = PlexVideoQuality(rawValue: rawValue) else {
                return
            }
            onSelectVideoQuality(quality)
        }

        @objc private func selectVideoDynamicRange(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let dynamicRange = PlexVideoDisplayDynamicRange(rawValue: rawValue) else {
                return
            }
            onSelectVideoDynamicRange(dynamicRange)
        }

        @objc private func selectVideoScalingMode(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let scalingMode = PlexVideoScalingMode(rawValue: rawValue) else {
                return
            }
            onSelectVideoScalingMode(scalingMode)
        }

        @objc private func skipMarker() {
            onSkipMarker()
        }

    }
}

@MainActor
struct PlexNativePlaybackRateObservationEpoch {
    struct Ticket: Equatable, Sendable {
        let generation: UInt
        let playerIdentifier: ObjectIdentifier
    }

    private var generation: UInt = 0
    private var currentTicket: Ticket?

    mutating func begin(player: AVPlayer) -> Ticket {
        generation &+= 1
        let ticket = Ticket(
            generation: generation,
            playerIdentifier: ObjectIdentifier(player)
        )
        currentTicket = ticket
        return ticket
    }

    mutating func invalidate() {
        generation &+= 1
        currentTicket = nil
    }

    func isCurrent(player: AVPlayer) -> Bool {
        guard let currentTicket else {
            return false
        }
        return currentTicket.generation == generation
            && currentTicket.playerIdentifier == ObjectIdentifier(player)
    }

    func playbackRate(
        for observedRawValue: Float,
        ticket: Ticket,
        player: AVPlayer
    ) -> PlexPlaybackRate? {
        guard currentTicket == ticket,
              ticket.generation == generation,
              ticket.playerIdentifier == ObjectIdentifier(player),
              abs(player.defaultRate - observedRawValue) < 0.001 else {
            return nil
        }
        return PlexPlaybackRate(remoteCommandValue: observedRawValue)
    }
}

extension PlexVideoDisplayDynamicRange {
    var avDisplayDynamicRange: AVDisplayDynamicRange {
        switch self {
        case .automatic: .automatic
        case .standard: .standard
        case .constrainedHigh: .constrainedHigh
        case .high: .high
        }
    }
}

private struct PlexSkipMarkerControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let action: PlexPlaybackMarkerAction?
    let perform: () -> Void

    var body: some View {
        Group {
            if let action {
                Button(action: perform) {
                    Label(action.label, systemImage: "forward.end.fill")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityHint(action.accessibilityHint)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: action?.id)
    }
}

@MainActor
@Observable
final class PlexPlayerSessionModel {
    private(set) var presentation: PlexPlaybackPresentation
    let engine = PlexPlaybackEngine()
    var isLoading = false
    var errorMessage: String?
    private(set) var qualitySuggestion: PlexPlaybackQualitySuggestion?
    private(set) var canRetryPlayback = false
    private(set) var isRefreshingQueue = false
    private(set) var isChangingShuffle = false
    private(set) var isAddingToQueue = false
    private(set) var isEditingQueue = false
    private(set) var queueErrorMessage: String?
    private(set) var postPlayHubs: [PlexHub] = []
    private(set) var isLoadingPostPlay = false
    private(set) var postPlayErrorMessage: String?
    private(set) var postPlayNextItem: PlexMediaItem?
    private(set) var postPlayCountdownTotalSeconds: Int?
    private(set) var postPlayCountdownRemainingSeconds: Int?

    @ObservationIgnored private let browserStore: PlexBrowserStore
    @ObservationIgnored private let settingsStore: PlexSettingsStore
    @ObservationIgnored private let userInteractionStore: PlexUserInteractionStore
    @ObservationIgnored private let coordinator: PlexPlayerCoordinator
    @ObservationIgnored private let downloadsStore: PlexDownloadsStore?
    @ObservationIgnored private let bandwidthRegistry: PlexPlaybackBandwidthRegistry
    @ObservationIgnored private let timelineReporter: PlexTimelineReportSequencer
    @ObservationIgnored private let nowPlayingController = PlexNowPlayingController()
    @ObservationIgnored private let nowPlayingArtworkLoader = PlexNowPlayingArtworkLoader()
    private var queue: PlexPlaybackQueue?
    @ObservationIgnored private var timelineTask: Task<Void, Never>?
    @ObservationIgnored private var seekTask: Task<Void, Never>?
    @ObservationIgnored private var nowPlayingArtworkTask: Task<Void, Never>?
    @ObservationIgnored private var postPlayCountdownTask: Task<Void, Never>?
    @ObservationIgnored private var timelineCadence = PlexTimelineReportCadence()
    @ObservationIgnored private var handledEndSessionIdentifier: String?
    @ObservationIgnored private var isTransitioning = false
    @ObservationIgnored private var didStop = false
    @ObservationIgnored private var sessionEpoch = PlexPlaybackSessionEpoch()
    @ObservationIgnored private var repeatMode: PlexPlaybackRepeatMode = .off
    @ObservationIgnored private var nativeMediaSelectionState = PlexNativeMediaSelectionState()
    @ObservationIgnored private var automaticMarkerTransition = PlexAutomaticPlaybackMarkerTransition()
    @ObservationIgnored private var pendingRewindOnResumeRequest: PlexPlaybackSeekSequence.Request?
    @ObservationIgnored private var qualitySuggestionState =
        PlexPlaybackQualitySuggestionSessionState()

    init(
        presentation: PlexPlaybackPresentation,
        browserStore: PlexBrowserStore,
        settingsStore: PlexSettingsStore,
        userInteractionStore: PlexUserInteractionStore,
        coordinator: PlexPlayerCoordinator,
        downloadsStore: PlexDownloadsStore? = nil,
        bandwidthRegistry: PlexPlaybackBandwidthRegistry = PlexPlaybackBandwidthRegistry()
    ) {
        self.presentation = presentation
        self.browserStore = browserStore
        self.settingsStore = settingsStore
        self.userInteractionStore = userInteractionStore
        self.coordinator = coordinator
        self.downloadsStore = downloadsStore
        self.bandwidthRegistry = bandwidthRegistry
        let offlinePackageID = presentation.offlinePackageID
        timelineReporter = PlexTimelineReportSequencer { [browserStore, downloadsStore] update in
            if let offlinePackageID, let downloadsStore {
                return await downloadsStore.recordOfflineTimeline(
                    packageID: offlinePackageID,
                    update: update
                )
            }
            return await browserStore.reportTimeline(update)
        }
        queue = presentation.queue
    }

    var playbackMethodLabel: String {
        isOfflinePlayback ? "Offline" : presentation.plan.method.label
    }

    var playbackStatusLabel: String {
        engine.status.label
    }

    var playbackWaitingReasonLabel: String? {
        engine.waitingReason?.diagnosticLabel
    }

    var playbackMetricDiagnosticFacts: [PlexPlaybackMetricDiagnosticFact] {
        engine.metricFacts?.diagnosticFacts ?? []
    }

    var showsVideoPreparationStage: Bool {
        PlexVideoPreparationPolicy.shouldPresent(
            mediaKind: presentation.plan.mediaKind,
            status: engine.status,
            isLoading: isLoading
        )
    }

    var mediaSelection: PlexPlaybackMediaSelection {
        PlexPlaybackMediaSelection(
            item: presentation.item,
            source: presentation.plan.source
        )
    }

    var serverManagedMediaSelection: PlexServerManagedMediaSelection {
        PlexServerManagedMediaSelection(
            selection: mediaSelection,
            nativeAvailability: nativeMediaSelectionState.availability
        )
    }

    var videoQualitySelection: PlexVideoQualitySelection {
        let isVideo = presentation.item.media.indices.contains(presentation.plan.source.mediaIndex)
            && presentation.item.media[presentation.plan.source.mediaIndex]
                .videoCodec?.nilIfBlank != nil
        return PlexVideoQualitySelection(
            selectedQuality: presentation.videoQuality,
            isVideo: isVideo,
            canChange: isVideo
                && !isOfflinePlayback
                && !isQueueBusy
                && pendingRewindOnResumeRequest == nil
                && PlexPlaybackReconfigurationPolicy(status: engine.status).canReload
        )
    }

    var canChangeMediaSelection: Bool {
        !isOfflinePlayback
            && !isQueueBusy
            && pendingRewindOnResumeRequest == nil
            && mediaSelection.partID != nil
            && PlexPlaybackReconfigurationPolicy(status: engine.status).canReload
    }

    var nativeMediaSelectionGeneration: UInt {
        nativeMediaSelectionState.generation
    }

    var queuePresentation: PlexPlaybackQueuePresentation? {
        queue?.presentation
    }

    var isUpdatingQueue: Bool {
        isRefreshingQueue || isChangingShuffle || isAddingToQueue || isEditingQueue
    }

    var hasPostPlayPresentation: Bool {
        postPlayNextItem != nil
            || isLoadingPostPlay
            || postPlayErrorMessage != nil
            || !postPlayHubs.isEmpty
    }

    var isPostPlayCountdownActive: Bool {
        postPlayCountdownRemainingSeconds != nil
    }

    var supportsCurrentItemWatchedStateMutation: Bool {
        !isOfflinePlayback && browserStore.supportsWatchedStateMutation(for: presentation.item)
    }

    var supportsCurrentItemPersonalRating: Bool {
        !isOfflinePlayback && browserStore.supportsPersonalRatings
    }

    var isUpdatingCurrentItemWatchedState: Bool {
        browserStore.isUpdatingWatchedState(for: presentation.item)
    }

    var isUpdatingCurrentItemPersonalRating: Bool {
        browserStore.isUpdatingPersonalRating(for: presentation.item)
    }

    var canShowCurrentItemInLibrary: Bool {
        !isOfflinePlayback && PlexPlayerLibraryHandoffPolicy.canOpen(
            playbackServerIdentifier: presentation.serverIdentifier,
            browserServerIdentifier: activeBrowserServerIdentifier
        )
    }

    private var isOfflinePlayback: Bool {
        presentation.offlinePackageID != nil
    }

    func setCurrentItemWatched(_ watched: Bool) async throws {
        let ticket = PlexPlayerItemMutationTicket(presentation: presentation)
        let refreshedItem = try await browserStore.setWatched(watched, for: presentation.item)
        guard !didStop, ticket.accepts(presentation) else {
            return
        }
        replaceCurrentItem(with: refreshedItem)
    }

    func setCurrentItemPersonalRating(_ rating: Double?) async throws {
        let ticket = PlexPlayerItemMutationTicket(presentation: presentation)
        let refreshedItem = try await browserStore.setPersonalRating(
            rating,
            for: presentation.item
        )
        guard !didStop, ticket.accepts(presentation) else {
            return
        }
        replaceCurrentItem(with: refreshedItem)
    }

    func canAddToQueue(_ item: PlexMediaItem) -> Bool {
        guard !isQueueBusy,
              pendingRewindOnResumeRequest == nil,
              presentation.serverIdentifier?.nilIfBlank == activeBrowserServerIdentifier,
              let queue else {
            return false
        }
        return queue.canAdd(item)
    }

    func addToQueue(
        _ item: PlexMediaItem,
        insertion: PlexPlayQueueInsertion
    ) async throws {
        guard let ticket = currentSessionTicket, canAddToQueue(item),
              var updatedQueue = queue else {
            throw PlexAPIError.invalidPlayQueue
        }

        isAddingToQueue = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isAddingToQueue = false
                updatePlaybackControlAvailability()
            }
        }

        let page = try await browserStore.addToPlayQueue(
            item,
            queueID: updatedQueue.id,
            insertion: insertion
        )
        try checkCurrentSession(ticket)
        try updatedQueue.applyAddition(page)
        queue = updatedQueue
        queueErrorMessage = nil
        updateNowPlaying()
    }

    func canRemoveUpcomingItem(playQueueItemID: String) -> Bool {
        !isQueueBusy
            && pendingRewindOnResumeRequest == nil
            && queue?.canRemoveUpcomingItem(playQueueItemID: playQueueItemID) == true
    }

    func canMoveUpcomingItem(
        playQueueItemID: String,
        direction: PlexPlayQueueItemMoveDirection
    ) -> Bool {
        !isQueueBusy
            && pendingRewindOnResumeRequest == nil
            && queue?.moveRequest(
                for: playQueueItemID,
                direction: direction
            ) != nil
    }

    var canReorderUpcomingItems: Bool {
        !isQueueBusy
            && pendingRewindOnResumeRequest == nil
            && queue?.canReorderLoadedUpcomingItems == true
    }

    func removeUpcomingItem(playQueueItemID: String) {
        guard canRemoveUpcomingItem(playQueueItemID: playQueueItemID),
              let ticket = currentSessionTicket else {
            return
        }
        userInteractionStore.recordInteraction()
        Task {
            await removeUpcomingItem(
                playQueueItemID: playQueueItemID,
                ticket: ticket
            )
        }
    }

    func moveUpcomingItem(
        playQueueItemID: String,
        direction: PlexPlayQueueItemMoveDirection
    ) {
        guard canMoveUpcomingItem(
            playQueueItemID: playQueueItemID,
            direction: direction
        ), let move = queue?.moveRequest(
            for: playQueueItemID,
            direction: direction
        ), let ticket = currentSessionTicket else {
            return
        }
        userInteractionStore.recordInteraction()
        Task {
            await moveUpcomingItem(
                move: move,
                ticket: ticket
            )
        }
    }

    @discardableResult
    func moveUpcomingItems(
        fromOffsets sourceOffsets: IndexSet,
        toOffset destinationOffset: Int
    ) -> Bool {
        guard canReorderUpcomingItems,
              let move = queue?.moveRequest(
                  fromUpcomingOffsets: sourceOffsets,
                  toUpcomingOffset: destinationOffset
              ), let ticket = currentSessionTicket else {
            return false
        }
        userInteractionStore.recordInteraction()
        Task {
            await moveUpcomingItem(move: move, ticket: ticket)
        }
        return true
    }

    var artworkServerURL: URL? {
        browserStore.connectionStore.resolvedServerURL
    }

    var artworkToken: String {
        browserStore.connectionStore.settings.trimmedServerToken
    }

    private func replaceCurrentItem(with item: PlexMediaItem) {
        replacePresentation(PlexPlaybackPresentation(
            item: item,
            plan: presentation.plan,
            queue: queue,
            videoQuality: presentation.videoQuality,
            serverIdentifier: presentation.serverIdentifier,
            queueSourcePreference: presentation.queueSourcePreference
        ))
    }

    private func replacePresentation(_ presentation: PlexPlaybackPresentation) {
        let itemChanged = self.presentation.item.ratingKey != presentation.item.ratingKey
        if itemChanged
            || self.presentation.plan.sessionIdentifier != presentation.plan.sessionIdentifier {
            cancelPendingRewindOnResume()
            automaticMarkerTransition.reset()
        }
        if itemChanged {
            qualitySuggestion = nil
            qualitySuggestionState.moveToItem(itemKey: presentation.item.ratingKey)
        }
        if self.presentation.plan.sessionIdentifier != presentation.plan.sessionIdentifier {
            clearPostPlay()
        }
        self.presentation = presentation
        coordinator.updateCurrentPlayback(for: self, presentation: presentation)
    }

    private func clearPostPlay() {
        postPlayCountdownTask?.cancel()
        postPlayCountdownTask = nil
        postPlayHubs = []
        isLoadingPostPlay = false
        postPlayErrorMessage = nil
        postPlayNextItem = nil
        postPlayCountdownTotalSeconds = nil
        postPlayCountdownRemainingSeconds = nil
    }

    var artworkClientContext: PlexClientContext {
        PlexClientContext(
            clientIdentifier: browserStore.connectionStore.settings.clientIdentifier
        )
    }

    func requestQueueRefresh() {
        Task {
            await refreshQueueWindow()
        }
    }

    func playUpcomingItem(playQueueItemID: String) {
        guard pendingRewindOnResumeRequest == nil,
              let ticket = currentSessionTicket else {
            return
        }
        userInteractionStore.recordInteraction()
        clearPostPlayCountdown()
        Task {
            await navigate(toPlayQueueItemID: playQueueItemID, ticket: ticket)
        }
    }

    func requestPostPlayRefresh() {
        guard canShowCurrentItemInLibrary, let ticket = currentSessionTicket else {
            return
        }
        Task {
            await loadPostPlay(ticket: ticket)
        }
    }

    func playPostPlayItem(_ item: PlexMediaItem) {
        userInteractionStore.recordInteraction()
        if postPlayNextItem?.playQueueItemID?.nilIfBlank == item.playQueueItemID?.nilIfBlank,
           postPlayNextItem?.ratingKey == item.ratingKey {
            playPostPlayNextItem()
            return
        }
        guard let ticket = currentSessionTicket,
              canShowCurrentItemInLibrary,
              engine.status == .ended,
              postPlayHubs.lazy.flatMap(\.metadata).contains(where: {
                  $0.ratingKey == item.ratingKey
              }) else {
            return
        }
        Task {
            await startPostPlayItem(item, ticket: ticket)
        }
    }

    func playPostPlayNextItem() {
        guard postPlayNextItem != nil,
              engine.status == .ended,
              let ticket = currentSessionTicket else {
            return
        }
        userInteractionStore.recordInteraction()
        clearPostPlayCountdown()
        Task {
            await navigate(
                .next,
                completedCurrentItem: false,
                ticket: ticket
            )
        }
    }

    func cancelPostPlayAutoplay() {
        userInteractionStore.recordInteraction()
        clearPostPlayCountdown()
    }

    private func clearPostPlayCountdown() {
        postPlayCountdownTask?.cancel()
        postPlayCountdownTask = nil
        postPlayCountdownTotalSeconds = nil
        postPlayCountdownRemainingSeconds = nil
    }

    func setShuffled(_ isShuffled: Bool) {
        guard pendingRewindOnResumeRequest == nil,
              let ticket = currentSessionTicket else {
            return
        }
        userInteractionStore.recordInteraction()
        Task {
            await changeShuffle(to: isShuffled, ticket: ticket)
        }
    }

    func setRepeatMode(_ repeatMode: PlexPlaybackRepeatMode) {
        guard repeatMode != self.repeatMode,
              repeatMode != .all || queue?.canRepeatAll == true else {
            return
        }
        userInteractionStore.recordInteraction()
        self.repeatMode = repeatMode
        coordinator.updateRepeatMode(
            for: self,
            repeatMode: repeatMode,
            canRepeatAll: queue?.canRepeatAll == true
        )
        nowPlayingController.updateRepeatMode(repeatMode)
    }

    func refreshQueueWindow() async {
        guard let ticket = currentSessionTicket, !isQueueBusy,
              var updatedQueue = queue,
              let currentQueueItemID = updatedQueue.currentItem.playQueueItemID else {
            return
        }

        isRefreshingQueue = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isRefreshingQueue = false
                updatePlaybackControlAvailability()
            }
        }

        do {
            let page = try await browserStore.refreshPlayQueueWindow(
                queueID: updatedQueue.id,
                centeredOn: currentQueueItemID
            )
            try checkCurrentSession(ticket)
            try updatedQueue.replaceWindow(with: page, centeredOn: currentQueueItemID)
            queue = updatedQueue
            queueErrorMessage = nil
            updateNowPlaying()
        } catch is CancellationError {
            return
        } catch {
            if isCurrentSession(ticket) {
                queueErrorMessage = error.localizedDescription
            }
        }
    }

    private func changeShuffle(
        to isShuffled: Bool,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async {
        guard isCurrentSession(ticket), !isQueueBusy,
              var updatedQueue = queue,
              updatedQueue.canChangeShuffle,
              updatedQueue.isShuffled != isShuffled else {
            return
        }

        isChangingShuffle = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isChangingShuffle = false
                updatePlaybackControlAvailability()
            }
        }

        do {
            let page = try await browserStore.setPlayQueueShuffled(
                isShuffled,
                queueID: updatedQueue.id
            )
            try checkCurrentSession(ticket)
            try updatedQueue.applyShuffleMutation(
                page,
                expectedShuffled: isShuffled
            )
            queue = updatedQueue
            queueErrorMessage = nil
            updateNowPlaying()
        } catch is CancellationError {
            return
        } catch {
            if isCurrentSession(ticket) {
                queueErrorMessage = error.localizedDescription
            }
        }
    }

    private func removeUpcomingItem(
        playQueueItemID: String,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async {
        guard isCurrentSession(ticket), !isQueueBusy,
              var updatedQueue = queue,
              updatedQueue.canRemoveUpcomingItem(
                  playQueueItemID: playQueueItemID
              ) else {
            return
        }

        isEditingQueue = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isEditingQueue = false
                updatePlaybackControlAvailability()
            }
        }

        do {
            let page = try await browserStore.removePlayQueueItem(
                queueID: updatedQueue.id,
                playQueueItemID: playQueueItemID
            )
            try checkCurrentSession(ticket)
            try updatedQueue.applyRemoval(
                page,
                removedPlayQueueItemID: playQueueItemID
            )
            queue = updatedQueue
            queueErrorMessage = nil
            updateNowPlaying()
        } catch is CancellationError {
            return
        } catch {
            if isCurrentSession(ticket) {
                queueErrorMessage = error.localizedDescription
            }
        }
    }

    private func moveUpcomingItem(
        move: PlexPlayQueueItemMove,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async {
        guard isCurrentSession(ticket), !isQueueBusy,
              var updatedQueue = queue,
              updatedQueue.canApplyMoveRequest(move) else {
            return
        }

        isEditingQueue = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isEditingQueue = false
                updatePlaybackControlAvailability()
            }
        }

        do {
            let page = try await browserStore.movePlayQueueItem(
                queueID: updatedQueue.id,
                move: move
            )
            try checkCurrentSession(ticket)
            try updatedQueue.applyMove(page, request: move)
            queue = updatedQueue
            queueErrorMessage = nil
            updateNowPlaying()
        } catch is CancellationError {
            return
        } catch {
            if isCurrentSession(ticket) {
                queueErrorMessage = error.localizedDescription
            }
        }
    }

    var activeMarkerAction: PlexPlaybackMarkerAction? {
        switch engine.status {
        case .playing, .paused, .buffering:
            return PlexPlaybackMarkerAction.manual(
                in: presentation.item.markers,
                at: engine.position,
                duration: playbackDuration,
                preferences: settingsStore.playbackMarkerPreferences
            )
        case .idle, .preparing, .ended, .failed:
            return nil
        }
    }

    private var markerActionAtCurrentPosition: PlexPlaybackMarkerAction? {
        switch engine.status {
        case .playing, .paused, .buffering:
            PlexPlaybackMarkerAction.active(
                in: presentation.item.markers,
                at: engine.position,
                duration: playbackDuration
            )
        case .idle, .preparing, .ended, .failed:
            nil
        }
    }

    func skipActiveMarker() {
        guard let action = activeMarkerAction else {
            return
        }
        requestSeek(to: action.targetTime)
    }

    func playbackPositionDidChange() {
        evaluateAutomaticMarkerSkip()
    }

    func playbackMarkerPreferencesDidChange() {
        evaluateAutomaticMarkerSkip()
    }

    private func evaluateQualitySuggestion() {
        guard !qualitySuggestionState.isSuppressed,
              qualitySuggestion == nil else {
            return
        }
        switch engine.status {
        case .playing, .paused, .buffering:
            break
        case .idle, .preparing, .ended, .failed:
            return
        }

        let connectionKind = browserStore.connectionStore.activeConnectionKind
            ?? settingsStore.cachedConnectionKind
        qualitySuggestion = PlexPlaybackQualitySuggestionPolicy.suggestion(
            isEnabled: settingsStore.qualitySuggestionsEnabled,
            selection: videoQualitySelection,
            sourceBitrate: selectedSourceVideoBitrate,
            maximumQuality: settingsStore.videoQuality(for: connectionKind),
            isTranscoding: presentation.plan.method == .transcode,
            metrics: engine.metricFacts,
            excludedQualities: qualitySuggestionState.acceptedQualities
        )
    }

    private var selectedSourceVideoBitrate: Int? {
        let mediaIndex = presentation.plan.source.mediaIndex
        guard presentation.item.media.indices.contains(mediaIndex) else {
            return nil
        }
        return presentation.item.media[mediaIndex].bitrate
    }

    func selectAudioStream(_ streamID: Int) {
        guard canChangeMediaSelection,
              mediaSelection.canSelectAudioStream(streamID),
              let ticket = currentSessionTicket else {
            return
        }
        userInteractionStore.recordInteraction()
        Task {
            await changeMediaSelection(audioStreamID: streamID, ticket: ticket)
        }
    }

    func selectSubtitleStream(_ streamID: Int?) {
        guard canChangeMediaSelection,
              mediaSelection.canSelectSubtitleStream(streamID),
              let ticket = currentSessionTicket else {
            return
        }
        userInteractionStore.recordInteraction()
        Task {
            await changeMediaSelection(subtitleStreamID: streamID ?? 0, ticket: ticket)
        }
    }

    func selectVideoQuality(_ quality: PlexVideoQuality) {
        guard videoQualitySelection.canSelect(quality),
              let ticket = currentSessionTicket else {
            return
        }
        qualitySuggestion = nil
        qualitySuggestionState.suppress()
        userInteractionStore.recordInteraction()
        Task {
            await changeVideoQuality(to: quality, ticket: ticket)
        }
    }

    func playbackMetricsDidChange() {
        persistLastMeasuredBandwidth()
        evaluateQualitySuggestion()
    }

    private func persistLastMeasuredBandwidth() {
        guard let sample = engine.metricFacts?.lastMeasuredBandwidth,
              let serverIdentifier = presentation.serverIdentifier?.nilIfBlank else {
            return
        }
        Task { [bandwidthRegistry] in
            do {
                try await bandwidthRegistry.record(sample, for: serverIdentifier)
            } catch {
                plexPlayerLogger.error(
                    "Could not persist playback bandwidth: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func qualitySuggestionSettingsDidChange() {
        guard settingsStore.qualitySuggestionsEnabled else {
            qualitySuggestion = nil
            return
        }
        evaluateQualitySuggestion()
    }

    func acceptQualitySuggestion() {
        guard let suggestion = qualitySuggestion,
              let ticket = currentSessionTicket else {
            return
        }
        qualitySuggestion = nil
        guard videoQualitySelection.canSelect(suggestion.targetQuality) else {
            qualitySuggestionState.suppress()
            return
        }

        qualitySuggestionState.recordAccepted(suggestion.targetQuality)
        userInteractionStore.recordInteraction()
        Task {
            await changeVideoQuality(to: suggestion.targetQuality, ticket: ticket)
        }
    }

    func dismissQualitySuggestion() {
        guard qualitySuggestion != nil else {
            return
        }
        qualitySuggestion = nil
        qualitySuggestionState.suppress()
    }

    func selectPlaybackRate(_ playbackRate: PlexPlaybackRate) {
        guard currentSessionTicket != nil else {
            return
        }
        userInteractionStore.recordInteraction()
        changePlaybackRate(playbackRate)
    }

    func updateNativeMediaSelectionAvailability(
        _ availability: PlexNativeMediaSelectionAvailability,
        generation: UInt
    ) {
        guard nativeMediaSelectionState.accept(
            availability,
            generation: generation
        ) else {
            return
        }
        nowPlayingController.updateLanguageOptions(nowPlayingLanguageOptions)
        updateServerManagedMediaSelectionControls()
    }

    func playbackStatusDidChange() {
        guard !didStop, coordinator.isActive(self) else {
            return
        }
        switch engine.status {
        case .playing, .paused, .buffering:
            evaluateQualitySuggestion()
        case .idle, .preparing, .ended, .failed:
            qualitySuggestion = nil
        }
        evaluateAutomaticMarkerSkip()
        coordinator.updateTransport(
            for: self,
            status: transportStatus,
            canToggle: !isQueueBusy
        )
        updateNowPlaying()
    }

    func playbackTimeDidJump() {
        guard let ticket = currentSessionTicket else {
            return
        }
        switch engine.status {
        case .playing, .paused, .buffering:
            break
        case .idle, .preparing, .ended, .failed:
            return
        }

        updateNowPlaying(force: true)
        Task { [weak self] in
            guard let self,
                  !Task.isCancelled,
                  isCurrentSession(ticket) else {
                return
            }
            await reportTimeline(state: timelineState, ticket: ticket)
        }
    }

    func start() async {
        guard timelineTask == nil else {
            return
        }

        let ticket = sessionEpoch.activate()
        didStop = false
        qualitySuggestion = nil
        qualitySuggestionState.beginSession(itemKey: presentation.item.ratingKey)
        pendingRewindOnResumeRequest = nil
        automaticMarkerTransition.reset()
        clearPostPlay()
        isLoading = true
        defer {
            if isCurrentSession(ticket) {
                isLoading = false
            }
        }

        do {
            canRetryPlayback = false
            clearNativeMediaSelectionAvailability()
            try await engine.load(plan: presentation.plan)
            guard isCurrentSession(ticket) else {
                engine.stop()
                return
            }
            installNavigationActions()
            activateNowPlaying()
            startTimelineReporting(ticket: ticket)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSession(ticket) else {
                return
            }
            canRetryPlayback = false
            errorMessage = error.localizedDescription
            clearNowPlayingArtworkLoad()
            coordinator.clearPlaybackControls(for: self)
        }
    }

    func stop(deactivateNowPlaying: Bool = true) {
        guard didStop == false else {
            return
        }

        let stoppedTimeline = PlexTimelineUpdate(
            ratingKey: presentation.plan.ratingKey,
            state: .stopped,
            time: Int(engine.position * 1_000),
            duration: Int((playbackDuration ?? 0) * 1_000),
            sessionIdentifier: presentation.plan.sessionIdentifier,
            playQueueItemID: queue?.currentItem.playQueueItemID,
            continuing: false
        )
        didStop = true
        qualitySuggestion = nil
        qualitySuggestionState.reset()
        automaticMarkerTransition.reset()
        sessionEpoch.invalidate()
        canRetryPlayback = false
        isLoading = false
        isTransitioning = false
        isRefreshingQueue = false
        isChangingShuffle = false
        isAddingToQueue = false
        isEditingQueue = false
        clearPostPlay()
        timelineTask?.cancel()
        timelineTask = nil
        seekTask?.cancel()
        seekTask = nil
        pendingRewindOnResumeRequest = nil
        clearNowPlayingArtworkLoad()
        engine.stop()
        if deactivateNowPlaying {
            nowPlayingController.deactivate()
        }
        coordinator.clearPlaybackControls(for: self)

        let timelineReporter = timelineReporter
        Task {
            _ = await timelineReporter.report(stoppedTimeline)
        }
    }

    private func reportTimelineIfNeeded(ticket: PlexPlaybackSessionEpoch.Ticket) async {
        guard isCurrentSession(ticket), !Task.isCancelled else {
            return
        }
        coordinator.updateTransport(
            for: self,
            status: transportStatus,
            canToggle: !isQueueBusy
        )
        if case .failed(let message) = engine.status {
            canRetryPlayback = PlexPlaybackRecoveryPolicy.canRetry(
                status: engine.status,
                isLoading: isLoading,
                isActive: coordinator.isActive(self),
                didStop: didStop
            )
            errorMessage = message
            timelineTask?.cancel()
            timelineTask = nil
            clearNowPlayingArtworkLoad()
            if coordinator.isActive(self) {
                nowPlayingController.deactivate()
                coordinator.clearPlaybackControls(for: self)
            }
            return
        }

        if engine.status == .ended {
            await handlePlaybackEnded(ticket: ticket)
            return
        }

        updateNowPlaying()
        let state = timelineState
        guard timelineCadence.shouldReport(state: state, at: .now) else {
            return
        }

        await reportTimeline(state: state, ticket: ticket)
    }

    private func reportTimeline(
        state: PlexTimelineState,
        continuing: Bool? = nil,
        time: Int? = nil,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async {
        let identity = PlexTimelineRequestIdentity(
            sessionIdentifier: presentation.plan.sessionIdentifier,
            ticket: ticket
        )
        let update = PlexTimelineUpdate(
            ratingKey: presentation.plan.ratingKey,
            state: state,
            time: time ?? Int(engine.position * 1_000),
            duration: Int((playbackDuration ?? 0) * 1_000),
            sessionIdentifier: identity.sessionIdentifier,
            playQueueItemID: queue?.currentItem.playQueueItemID,
            continuing: continuing
        )
        guard !Task.isCancelled, isCurrentTimelineRequest(identity) else {
            return
        }
        let response = await timelineReporter.report(update)
        guard !Task.isCancelled, isCurrentTimelineRequest(identity) else {
            return
        }
        if state != .stopped, let termination = response?.termination {
            handleServerTermination(termination)
            return
        }
        timelineCadence.record(state: state, at: .now)
    }

    private func handleServerTermination(_ termination: PlexTimelineResponse.Termination) {
        guard !didStop else {
            return
        }
        didStop = true
        automaticMarkerTransition.reset()
        sessionEpoch.invalidate()
        canRetryPlayback = false
        isLoading = false
        isTransitioning = false
        isRefreshingQueue = false
        isChangingShuffle = false
        isAddingToQueue = false
        isEditingQueue = false
        clearPostPlay()
        timelineTask?.cancel()
        timelineTask = nil
        seekTask?.cancel()
        seekTask = nil
        pendingRewindOnResumeRequest = nil
        clearNowPlayingArtworkLoad()
        engine.stop()
        nowPlayingController.deactivate()
        coordinator.clearPlaybackControls(for: self)
        errorMessage = termination.message
    }

    func retryPlayback() {
        guard canRetryPlayback, let ticket = currentSessionTicket else {
            return
        }
        Task {
            await retryFailedPlayback(ticket: ticket)
        }
    }

    private func retryFailedPlayback(ticket: PlexPlaybackSessionEpoch.Ticket) async {
        guard PlexPlaybackRecoveryPolicy.canRetry(
            status: engine.status,
            isLoading: isLoading,
            isActive: coordinator.isActive(self),
            didStop: didStop
        ), isCurrentSession(ticket) else {
            return
        }

        isLoading = true
        canRetryPlayback = false
        errorMessage = nil
        let position = engine.position
        let recoveryRequest = PlexPlaybackRecoveryRequest(
            plan: presentation.plan,
            videoQuality: presentation.videoQuality,
            position: position
        )
        defer {
            if isCurrentSession(ticket) {
                isLoading = false
            }
        }

        do {
            let refreshedItem = try await browserStore.refreshedPlayableDetails(
                for: presentation.item
            )
            try checkCurrentSession(ticket)
            let plan = try await browserStore.playbackPlan(
                for: refreshedItem,
                source: recoveryRequest.source,
                videoQuality: recoveryRequest.videoQuality,
                startTimeOverride: recoveryRequest.startTime,
                forceServerMediaSelection: recoveryRequest.forceServerMediaSelection
            )
            try checkCurrentSession(ticket)

            await reportTimeline(
                state: .stopped,
                time: Int(recoveryRequest.startTime * 1_000),
                ticket: ticket
            )
            try checkCurrentSession(ticket)

            replacePresentation(PlexPlaybackPresentation(
                item: refreshedItem,
                plan: plan,
                queue: queue,
                videoQuality: presentation.videoQuality,
                serverIdentifier: presentation.serverIdentifier,
                queueSourcePreference: presentation.queueSourcePreference
            ))
            handledEndSessionIdentifier = nil
            timelineCadence.reset()
            clearNativeMediaSelectionAvailability()
            try await engine.load(plan: plan)
            try checkCurrentSession(ticket)
            installNavigationActions()
            activateNowPlaying()
            startTimelineReporting(ticket: ticket)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSession(ticket) else {
                return
            }
            canRetryPlayback = PlexPlaybackRecoveryPolicy.canRetry(
                status: engine.status,
                isLoading: false,
                isActive: coordinator.isActive(self),
                didStop: didStop
            )
            errorMessage = error.localizedDescription
        }
    }

    private func startTimelineReporting(ticket: PlexPlaybackSessionEpoch.Ticket) {
        timelineTask?.cancel()
        timelineTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, isCurrentSession(ticket) else {
                    return
                }
                await reportTimelineIfNeeded(ticket: ticket)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var timelineState: PlexTimelineState {
        switch engine.status {
        case .playing:
            .playing
        case .buffering, .preparing:
            .buffering
        case .paused:
            .paused
        case .idle, .ended, .failed:
            .stopped
        }
    }

    private var transportStatus: PlexPlaybackStatus {
        pendingRewindOnResumeRequest == nil ? engine.status : .playing
    }

    private var playbackDuration: TimeInterval? {
        engine.duration ?? presentation.plan.duration
    }

    private var isQueueBusy: Bool {
        isTransitioning
            || isRefreshingQueue
            || isChangingShuffle
            || isAddingToQueue
            || isEditingQueue
    }

    private var activeBrowserServerIdentifier: String? {
        browserStore.connectionStore.activeConnection?.serverID
            ?? browserStore.connectionStore.settings.selectedServerIdentifier?.nilIfBlank
    }

    private var currentSessionTicket: PlexPlaybackSessionEpoch.Ticket? {
        guard !didStop, coordinator.isActive(self) else {
            return nil
        }
        return sessionEpoch.currentTicket()
    }

    private func isCurrentSession(_ ticket: PlexPlaybackSessionEpoch.Ticket) -> Bool {
        !didStop && coordinator.isActive(self) && sessionEpoch.isCurrent(ticket)
    }

    private func isCurrentTimelineRequest(_ identity: PlexTimelineRequestIdentity) -> Bool {
        !didStop
            && coordinator.isActive(self)
            && identity.isCurrent(
                sessionIdentifier: presentation.plan.sessionIdentifier,
                epoch: sessionEpoch
            )
    }

    private func checkCurrentSession(
        _ ticket: PlexPlaybackSessionEpoch.Ticket
    ) throws {
        try Task.checkCancellation()
        guard isCurrentSession(ticket) else {
            throw CancellationError()
        }
    }

    private func requestNavigation(_ direction: PlexPlaybackQueueDirection) {
        guard pendingRewindOnResumeRequest == nil,
              let ticket = currentSessionTicket else {
            return
        }
        userInteractionStore.recordInteraction()
        clearPostPlayCountdown()
        Task {
            await navigate(
                direction,
                completedCurrentItem: false,
                ticket: ticket
            )
        }
    }

    private var remotePlaybackActions: PlexRemotePlaybackActions {
        PlexRemotePlaybackActions(
            play: { [weak self] in
                self?.performTransportAction(.play)
            },
            pause: { [weak self] in
                self?.performTransportAction(.pause)
            },
            togglePlayPause: { [weak self] in
                self?.togglePlayback()
            },
            stop: { [weak self] in
                self?.requestStop()
            },
            seek: { [weak self] position in
                self?.requestSeek(to: position)
            },
            skip: { [weak self] offset in
                self?.requestSkip(by: offset)
            },
            selectAudioStream: { [weak self] streamID in
                self?.selectAudioStream(streamID)
            },
            selectSubtitleStream: { [weak self] streamID in
                self?.selectSubtitleStream(streamID)
            },
            changePlaybackRate: { [weak self] playbackRate in
                self?.changePlaybackRate(playbackRate)
            },
            changeShuffle: { [weak self] isShuffled in
                self?.setShuffled(isShuffled)
            },
            changeRepeatMode: { [weak self] repeatMode in
                self?.setRepeatMode(repeatMode)
            },
            previous: { [weak self] in
                self?.requestNavigation(.previous)
            },
            next: { [weak self] in
                self?.requestNavigation(.next)
            }
        )
    }

    private func togglePlayback() {
        guard let action = PlexRewindOnResumePolicy.transportAction(
            status: engine.status,
            hasPendingRewind: pendingRewindOnResumeRequest != nil
        ) else {
            return
        }
        performTransportAction(action)
    }

    private func performTransportAction(_ action: PlexPlaybackTransportAction) {
        guard !isQueueBusy,
              let ticket = currentSessionTicket,
              PlexRewindOnResumePolicy.transportAction(
                  status: engine.status,
                  hasPendingRewind: pendingRewindOnResumeRequest != nil
              ) == action else {
            return
        }
        userInteractionStore.recordInteraction()

        switch action {
        case .play:
            resumePlayback(ticket: ticket)
            return
        case .pause:
            cancelPendingRewindOnResume()
            engine.pause()
        }
        coordinator.updateTransport(
            for: self,
            status: transportStatus,
            canToggle: true
        )
        updateNowPlaying(force: true)
    }

    private func resumePlayback(ticket: PlexPlaybackSessionEpoch.Ticket) {
        guard let action = PlexRewindOnResumePolicy.action(
            status: engine.status,
            position: engine.position,
            preference: settingsStore.rewindOnResume
        ) else {
            return
        }

        switch action {
        case .playImmediately:
            engine.play()
            coordinator.updateTransport(
                for: self,
                status: engine.status,
                canToggle: true
            )
            updateNowPlaying(force: true)

        case .seekThenPlay(let target):
            seekTask?.cancel()
            let request = engine.reserveSeek(to: target)
            pendingRewindOnResumeRequest = request
            updatePlaybackControlAvailability()
            seekTask = Task { [weak self] in
                guard let self else {
                    return
                }
                let completed = await engine.performSeek(request)
                guard !Task.isCancelled,
                      isCurrentSession(ticket),
                      pendingRewindOnResumeRequest == request else {
                    return
                }

                pendingRewindOnResumeRequest = nil
                seekTask = nil
                if !completed {
                    engine.cancelPendingSeek()
                }
                engine.play()
                updatePlaybackControlAvailability()
                updateNowPlaying(force: true)
                await reportTimeline(state: timelineState, ticket: ticket)
            }
        }
    }

    private func cancelPendingRewindOnResume() {
        guard pendingRewindOnResumeRequest != nil else {
            return
        }
        pendingRewindOnResumeRequest = nil
        seekTask?.cancel()
        seekTask = nil
        engine.cancelPendingSeek()
        updatePlaybackControlAvailability()
    }

    private func requestStop() {
        guard currentSessionTicket != nil else {
            return
        }
        userInteractionStore.recordInteraction()
        coordinator.close(self)
    }

    private func requestSeek(to position: TimeInterval) {
        guard let ticket = currentSessionTicket else {
            return
        }
        userInteractionStore.recordInteraction()
        cancelPendingRewindOnResume()
        performSeek(engine.reserveSeek(to: position), ticket: ticket)
    }

    private func evaluateAutomaticMarkerSkip() {
        guard !didStop, coordinator.isActive(self), let ticket = currentSessionTicket else {
            automaticMarkerTransition.reset()
            return
        }

        guard let action = automaticMarkerTransition.action(
            for: markerActionAtCurrentPosition,
            preferences: settingsStore.playbackMarkerPreferences
        ) else {
            return
        }

        performSeek(
            engine.reserveSeek(to: action.targetTime),
            ticket: ticket,
            automaticMarkerAction: action
        )
    }

    private func requestSkip(by offset: TimeInterval) {
        guard !isQueueBusy, let ticket = currentSessionTicket else {
            return
        }
        userInteractionStore.recordInteraction()
        cancelPendingRewindOnResume()
        performSeek(
            engine.reserveSkip(
                by: offset,
                duration: playbackDuration
            ),
            ticket: ticket
        )
    }

    private func performSeek(
        _ request: PlexPlaybackSeekSequence.Request,
        ticket: PlexPlaybackSessionEpoch.Ticket,
        automaticMarkerAction: PlexPlaybackMarkerAction? = nil
    ) {
        seekTask?.cancel()
        seekTask = Task { [weak self] in
            guard let self else {
                return
            }
            let completed = await engine.performSeek(request)
            guard completed, !Task.isCancelled, isCurrentSession(ticket) else {
                if let automaticMarkerAction {
                    automaticMarkerTransition.retry(automaticMarkerAction)
                }
                return
            }
            updateNowPlaying(force: true)
            await reportTimeline(state: timelineState, ticket: ticket)
        }
    }

    private func changePlaybackRate(_ playbackRate: PlexPlaybackRate) {
        engine.setPlaybackRate(playbackRate)
        coordinator.updatePlaybackRate(for: self, playbackRate: playbackRate)
        updateNowPlaying(force: true)
    }

    private func changeMediaSelection(
        audioStreamID: Int? = nil,
        subtitleStreamID: Int? = nil,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async {
        let policy = PlexPlaybackReconfigurationPolicy(status: engine.status)
        guard canChangeMediaSelection, policy.canReload,
              let partID = mediaSelection.partID,
              isCurrentSession(ticket) else {
            return
        }

        isTransitioning = true
        isLoading = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isLoading = false
                isTransitioning = false
                updatePlaybackControlAvailability()
            }
        }

        if policy.autoplay {
            engine.pause()
            updateNowPlaying(force: true)
        }
        let position = engine.position
        var committedReload = false
        do {
            try await browserStore.selectMediaStreams(
                partID: partID,
                audioStreamID: audioStreamID,
                subtitleStreamID: subtitleStreamID
            )
            try checkCurrentSession(ticket)
            let refreshedItem = try await browserStore.refreshedPlayableDetails(
                for: presentation.item
            )
            try checkCurrentSession(ticket)
            let plan = try await browserStore.playbackPlan(
                for: refreshedItem,
                source: presentation.plan.source,
                videoQuality: presentation.videoQuality,
                startTimeOverride: position,
                forceServerMediaSelection: true
            )
            try checkCurrentSession(ticket)

            await reportTimeline(
                state: .stopped,
                time: Int(position * 1_000),
                ticket: ticket
            )
            try checkCurrentSession(ticket)
            committedReload = true
            replacePresentation(PlexPlaybackPresentation(
                item: refreshedItem,
                plan: plan,
                queue: queue,
                videoQuality: presentation.videoQuality,
                serverIdentifier: presentation.serverIdentifier,
                queueSourcePreference: presentation.queueSourcePreference
            ))
            handledEndSessionIdentifier = nil
            timelineCadence.reset()
            clearNativeMediaSelectionAvailability()
            try await engine.load(plan: plan, autoplay: policy.autoplay)
            try checkCurrentSession(ticket)
            activateNowPlaying()
        } catch is CancellationError {
            return
        } catch {
            if !committedReload, policy.autoplay, isCurrentSession(ticket) {
                engine.play()
                updateNowPlaying(force: true)
            }
            if isCurrentSession(ticket) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func changeVideoQuality(
        to quality: PlexVideoQuality,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async {
        let policy = PlexPlaybackReconfigurationPolicy(status: engine.status)
        guard videoQualitySelection.canSelect(quality), policy.canReload,
              isCurrentSession(ticket) else {
            return
        }

        isTransitioning = true
        isLoading = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isLoading = false
                isTransitioning = false
                updatePlaybackControlAvailability()
            }
        }

        if policy.autoplay {
            engine.pause()
            updateNowPlaying(force: true)
        }
        let position = engine.position
        var committedReload = false
        do {
            let plan = try await browserStore.playbackPlan(
                for: presentation.item,
                source: presentation.plan.source,
                videoQuality: quality,
                startTimeOverride: position
            )
            try checkCurrentSession(ticket)

            await reportTimeline(
                state: .stopped,
                time: Int(position * 1_000),
                ticket: ticket
            )
            try checkCurrentSession(ticket)
            committedReload = true
            replacePresentation(PlexPlaybackPresentation(
                item: presentation.item,
                plan: plan,
                queue: queue,
                videoQuality: quality,
                serverIdentifier: presentation.serverIdentifier,
                queueSourcePreference: presentation.queueSourcePreference
            ))
            handledEndSessionIdentifier = nil
            timelineCadence.reset()
            clearNativeMediaSelectionAvailability()
            try await engine.load(plan: plan, autoplay: policy.autoplay)
            try checkCurrentSession(ticket)
            activateNowPlaying()
        } catch is CancellationError {
            return
        } catch {
            if !committedReload, policy.autoplay, isCurrentSession(ticket) {
                engine.play()
                updateNowPlaying(force: true)
            }
            if isCurrentSession(ticket) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateNowPlaying(force: Bool = false) {
        nowPlayingController.update(
            metadata: nowPlayingMetadata,
            status: engine.status,
            force: force
        )
    }

    private func activateNowPlaying() {
        clearNowPlayingArtworkLoad()
        nowPlayingController.activate(
            metadata: nowPlayingMetadata,
            status: engine.status,
            actions: remotePlaybackActions,
            canGoPrevious: queue?.canMovePrevious == true,
            canGoNext: queue?.canMoveNext == true,
            canSeek: !isQueueBusy,
            languageOptions: nowPlayingLanguageOptions,
            canChangeLanguageOptions: canChangeLanguageOptions,
            canChangeShuffle: queue?.canChangeShuffle == true && !isQueueBusy,
            isShuffled: queue?.isShuffled == true,
            repeatMode: repeatMode,
            canRepeatAll: queue?.canRepeatAll == true
        )
        updatePlaybackControlAvailability()
        beginNowPlayingArtworkLoad()
    }

    private func beginNowPlayingArtworkLoad() {
        guard let request = PlexNowPlayingArtworkRequest(
            item: presentation.item,
            serverURL: artworkServerURL,
            token: artworkToken,
            clientContext: artworkClientContext
        ) else {
            return
        }

        let sessionIdentifier = presentation.plan.sessionIdentifier
        let itemRatingKey = presentation.item.ratingKey
        let loader = nowPlayingArtworkLoader
        nowPlayingArtworkTask = Task { [weak self] in
            guard let image = await loader.load(request),
                  let self,
                  !Task.isCancelled,
                  coordinator.isActive(self),
                  presentation.plan.sessionIdentifier == sessionIdentifier else {
                return
            }
            nowPlayingController.updateArtwork(
                image,
                itemRatingKey: itemRatingKey
            )
        }
    }

    private func clearNowPlayingArtworkLoad() {
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = nil
        nowPlayingArtworkLoader.invalidate()
    }

    private func clearNativeMediaSelectionAvailability() {
        let hadAvailability = nativeMediaSelectionState.availability != nil
        nativeMediaSelectionState.beginReload()
        updateServerManagedMediaSelectionControls()
        guard hadAvailability else {
            return
        }
        nowPlayingController.updateLanguageOptions(nowPlayingLanguageOptions)
    }

    private func installNavigationActions() {
        coordinator.installTransport(
            for: self,
            status: engine.status,
            canToggle: !isQueueBusy,
            toggle: { [weak self] in
                self?.togglePlayback()
            },
            stop: { [weak self] in
                self?.requestStop()
            }
        )
        coordinator.installNavigation(
            for: self,
            previous: { [weak self] in
                self?.requestNavigation(.previous)
            },
            next: { [weak self] in
                self?.requestNavigation(.next)
            }
        )
        coordinator.installPlaybackRate(
            for: self,
            playbackRate: engine.playbackRate,
            action: { [weak self] playbackRate in
                self?.changePlaybackRate(playbackRate)
            }
        )
        coordinator.installVideoQuality(
            for: self,
            selection: videoQualitySelection,
            action: { [weak self] quality in
                self?.selectVideoQuality(quality)
            }
        )
        coordinator.installServerManagedMediaSelection(
            for: self,
            selection: serverManagedMediaSelection,
            canChange: canChangeMediaSelection,
            selectAudioStream: { [weak self] streamID in
                self?.selectAudioStream(streamID)
            },
            selectSubtitleStream: { [weak self] streamID in
                self?.selectSubtitleStream(streamID)
            }
        )
        coordinator.installSeeking(
            for: self,
            canSeek: !isQueueBusy,
            action: { [weak self] offset in
                self?.requestSkip(by: offset)
            }
        )
        coordinator.installShuffle(
            for: self,
            isShuffled: queue?.isShuffled == true,
            canChange: queue?.canChangeShuffle == true && !isQueueBusy,
            action: { [weak self] isShuffled in
                self?.setShuffled(isShuffled)
            }
        )
        coordinator.installRepeatMode(
            for: self,
            repeatMode: repeatMode,
            canRepeatAll: queue?.canRepeatAll == true,
            action: { [weak self] repeatMode in
                self?.setRepeatMode(repeatMode)
            }
        )
        updatePlaybackControlAvailability()
    }

    private func updatePlaybackControlAvailability() {
        let hasPendingRewind = pendingRewindOnResumeRequest != nil
        let canGoPrevious = queue?.canMovePrevious == true && !isQueueBusy && !hasPendingRewind
        let canGoNext = queue?.canMoveNext == true && !isQueueBusy && !hasPendingRewind
        let canChangeShuffle = queue?.canChangeShuffle == true && !isQueueBusy && !hasPendingRewind
        let isShuffled = queue?.isShuffled == true
        let canRepeatAll = queue?.canRepeatAll == true
        coordinator.updateTransport(
            for: self,
            status: transportStatus,
            canToggle: !isQueueBusy
        )
        coordinator.updateNavigation(
            for: self,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext
        )
        coordinator.updateSeeking(for: self, canSeek: !isQueueBusy && !hasPendingRewind)
        coordinator.updateVideoQuality(for: self, selection: videoQualitySelection)
        updateServerManagedMediaSelectionControls()
        nowPlayingController.updateNavigation(
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext
        )
        nowPlayingController.updateSeeking(canSeek: !isQueueBusy)
        nowPlayingController.updateLanguageCommandAvailability(
            canChange: canChangeLanguageOptions
        )
        coordinator.updateShuffle(
            for: self,
            isShuffled: isShuffled,
            canChange: canChangeShuffle
        )
        nowPlayingController.updateShuffle(
            canChange: canChangeShuffle,
            isShuffled: isShuffled
        )
        coordinator.updateRepeatMode(
            for: self,
            repeatMode: repeatMode,
            canRepeatAll: canRepeatAll
        )
        coordinator.updateQueueInsertion(
            for: self,
            canAdd: queue != nil
                && presentation.serverIdentifier?.nilIfBlank == activeBrowserServerIdentifier
                && !isQueueBusy,
            isAdding: isAddingToQueue
        )
        nowPlayingController.updateRepeatMode(repeatMode)
    }

    private func handlePlaybackEnded(ticket: PlexPlaybackSessionEpoch.Ticket) async {
        guard !isQueueBusy, isCurrentSession(ticket) else {
            return
        }
        let sessionIdentifier = presentation.plan.sessionIdentifier
        guard handledEndSessionIdentifier != sessionIdentifier else {
            return
        }
        handledEndSessionIdentifier = sessionIdentifier

        let completionAction = PlexPlaybackCompletionAction.resolve(
            repeatMode: repeatMode,
            canAdvance: queue?.canMoveNext == true,
            canResetQueue: queue?.canRepeatAll == true,
            completedItem: presentation.item,
            mediaKind: presentation.plan.mediaKind,
            duration: playbackDuration,
            autoplayPreferences: settingsStore.autoplayPreferences,
            lastInteractionDate: userInteractionStore.lastInteractionDate,
            isCinemaPreplayItem: queue?.isCurrentCinemaPreplayItem == true
        )
        switch completionAction {
        case .replayCurrent:
            await replayCurrentItem(ticket: ticket)
            return
        case .advanceNext:
            await navigate(
                .next,
                completedCurrentItem: true,
                ticket: ticket
            )
            return
        case .presentPostPlay(let autoAdvanceAfterSeconds):
            await presentQueuedPostPlay(
                autoAdvanceAfterSeconds: autoAdvanceAfterSeconds,
                ticket: ticket
            )
            return
        case .resetQueue:
            await resetQueueAndContinue(ticket: ticket)
            return
        case .stop:
            break
        }

        await finishCurrentItem(continuing: false, ticket: ticket)
        if isCurrentSession(ticket) {
            await loadPostPlay(ticket: ticket)
        }
    }

    private func presentQueuedPostPlay(
        autoAdvanceAfterSeconds: Int?,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async {
        do {
            let nextItem = try await resolveNextQueueItemForPostPlay(ticket: ticket)
            try checkCurrentSession(ticket)
            await finishCurrentItem(continuing: true, ticket: ticket)
            try checkCurrentSession(ticket)

            postPlayNextItem = nextItem
            startPostPlayCountdown(
                seconds: autoAdvanceAfterSeconds,
                ticket: ticket
            )
            Task { [weak self] in
                await self?.loadPostPlay(ticket: ticket)
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSession(ticket) else {
                return
            }
            errorMessage = error.localizedDescription
            await finishCurrentItem(continuing: false, ticket: ticket)
            if isCurrentSession(ticket) {
                await loadPostPlay(ticket: ticket)
            }
        }
    }

    private func resolveNextQueueItemForPostPlay(
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async throws -> PlexMediaItem {
        guard var updatedQueue = queue, updatedQueue.canMoveNext else {
            throw PlexAPIError.invalidPlayQueue
        }
        if updatedQueue.needsWindowRefresh(for: .next) {
            guard let currentQueueItemID = updatedQueue.currentItem.playQueueItemID else {
                throw PlexAPIError.invalidPlayQueue
            }
            let page = try await browserStore.refreshPlayQueueWindow(
                queueID: updatedQueue.id,
                centeredOn: currentQueueItemID
            )
            try checkCurrentSession(ticket)
            try updatedQueue.replaceWindow(with: page, centeredOn: currentQueueItemID)
        }
        guard let nextItem = updatedQueue.presentation.upcomingItems.first else {
            throw PlexAPIError.invalidPlayQueue
        }
        queue = updatedQueue
        queueErrorMessage = nil
        updatePlaybackControlAvailability()
        return nextItem
    }

    private func finishCurrentItem(
        continuing: Bool,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async {
        await reportTimeline(
            state: .stopped,
            continuing: continuing,
            time: Int((playbackDuration ?? engine.position) * 1_000),
            ticket: ticket
        )
        guard !isOfflinePlayback else {
            if isCurrentSession(ticket) {
                updateNowPlaying(force: true)
            }
            return
        }
        do {
            try checkCurrentSession(ticket)
            try await browserStore.markPlayedIfSupported(ratingKey: presentation.item.ratingKey)
            try checkCurrentSession(ticket)
        } catch is CancellationError {
            return
        } catch {
            if isCurrentSession(ticket) {
                errorMessage = error.localizedDescription
            }
        }
        if isCurrentSession(ticket) {
            updateNowPlaying(force: true)
        }
    }

    private func startPostPlayCountdown(
        seconds: Int?,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) {
        clearPostPlayCountdown()
        guard let seconds, seconds > 0 else {
            return
        }
        postPlayCountdownTotalSeconds = seconds
        postPlayCountdownRemainingSeconds = seconds
        postPlayCountdownTask = Task { [weak self] in
            guard let self else {
                return
            }
            for remaining in stride(from: seconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled,
                      isCurrentSession(ticket),
                      engine.status == .ended,
                      settingsStore.autoplayUpNext else {
                    if !Task.isCancelled {
                        clearPostPlayCountdown()
                    }
                    return
                }
                postPlayCountdownRemainingSeconds = remaining
            }
            postPlayCountdownTask = nil
            postPlayCountdownTotalSeconds = nil
            postPlayCountdownRemainingSeconds = nil
            await navigate(
                .next,
                completedCurrentItem: false,
                ticket: ticket
            )
        }
    }

    private func loadPostPlay(ticket: PlexPlaybackSessionEpoch.Ticket) async {
        guard canShowCurrentItemInLibrary,
              isCurrentSession(ticket), engine.status == .ended, !isLoadingPostPlay else {
            return
        }
        let itemTicket = PlexPlayerItemMutationTicket(presentation: presentation)
        isLoadingPostPlay = true
        postPlayErrorMessage = nil
        defer {
            if isCurrentSession(ticket), itemTicket.accepts(presentation) {
                isLoadingPostPlay = false
            }
        }

        do {
            let hubs = try await browserStore.postPlayHubs(for: presentation.item, count: 8)
            try checkCurrentSession(ticket)
            guard canShowCurrentItemInLibrary,
                  engine.status == .ended,
                  itemTicket.accepts(presentation) else {
                return
            }
            postPlayHubs = Array(hubs.prefix(4))
            postPlayErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard canShowCurrentItemInLibrary,
                  isCurrentSession(ticket),
                  engine.status == .ended,
                  itemTicket.accepts(presentation) else {
                return
            }
            postPlayErrorMessage = error.localizedDescription
        }
    }

    private func startPostPlayItem(
        _ selectedItem: PlexMediaItem,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async {
        guard canShowCurrentItemInLibrary,
              !isQueueBusy, isCurrentSession(ticket), engine.status == .ended else {
            return
        }

        isTransitioning = true
        isLoading = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isLoading = false
                isTransitioning = false
                updatePlaybackControlAvailability()
            }
        }

        do {
            let nextItem = try await browserStore.refreshedPlayableDetails(for: selectedItem)
            try checkCurrentSession(ticket)
            async let plan = browserStore.playbackPlan(
                for: nextItem,
                videoQuality: presentation.videoQuality
            )
            async let nextQueue = postPlayQueue(for: nextItem)
            let (resolvedPlan, resolvedQueue) = try await (plan, nextQueue)
            try checkCurrentSession(ticket)
            guard canShowCurrentItemInLibrary else {
                return
            }

            queue = resolvedQueue
            queueErrorMessage = nil
            replacePresentation(PlexPlaybackPresentation(
                item: nextItem,
                plan: resolvedPlan,
                queue: resolvedQueue,
                videoQuality: presentation.videoQuality,
                serverIdentifier: presentation.serverIdentifier
            ))
            timelineCadence.reset()
            handledEndSessionIdentifier = nil
            clearNativeMediaSelectionAvailability()
            try await engine.load(plan: resolvedPlan)
            try checkCurrentSession(ticket)
            installNavigationActions()
            activateNowPlaying()
        } catch is CancellationError {
            return
        } catch {
            if isCurrentSession(ticket) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func postPlayQueue(for item: PlexMediaItem) async throws -> PlexPlaybackQueue? {
        guard item.continuousPlayQueueType != nil else {
            return nil
        }
        return try await browserStore.continuousPlayQueue(for: item)
    }

    private func replayCurrentItem(ticket: PlexPlaybackSessionEpoch.Ticket) async {
        guard !isQueueBusy, isCurrentSession(ticket) else {
            return
        }

        isTransitioning = true
        isLoading = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isLoading = false
                isTransitioning = false
                updatePlaybackControlAvailability()
            }
        }

        do {
            try await transition(
                to: presentation.item,
                queue: queue,
                completedCurrentItem: true,
                startTimeOverride: 0,
                ticket: ticket
            )
        } catch is CancellationError {
            return
        } catch {
            if isCurrentSession(ticket) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetQueueAndContinue(ticket: PlexPlaybackSessionEpoch.Ticket) async {
        guard !isQueueBusy, isCurrentSession(ticket),
              var updatedQueue = queue, updatedQueue.canRepeatAll else {
            return
        }

        isTransitioning = true
        isLoading = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isLoading = false
                isTransitioning = false
                updatePlaybackControlAvailability()
            }
        }

        do {
            let page = try await browserStore.resetPlayQueue(queueID: updatedQueue.id)
            try checkCurrentSession(ticket)
            try updatedQueue.applyReset(page)
            try await transition(
                to: updatedQueue.currentItem,
                queue: updatedQueue,
                completedCurrentItem: true,
                startTimeOverride: 0,
                ticket: ticket
            )
        } catch is CancellationError {
            return
        } catch {
            if isCurrentSession(ticket) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func navigate(
        _ direction: PlexPlaybackQueueDirection,
        completedCurrentItem: Bool,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async {
        guard !isQueueBusy, isCurrentSession(ticket),
              var updatedQueue = queue, updatedQueue.canMove(direction) else {
            return
        }

        isTransitioning = true
        isLoading = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isLoading = false
                isTransitioning = false
                updatePlaybackControlAvailability()
            }
        }

        do {
            if updatedQueue.needsWindowRefresh(for: direction) {
                guard let currentQueueItemID = updatedQueue.currentItem.playQueueItemID else {
                    throw PlexAPIError.invalidPlayQueue
                }
                let page = try await browserStore.refreshPlayQueueWindow(
                    queueID: updatedQueue.id,
                    centeredOn: currentQueueItemID
                )
                try checkCurrentSession(ticket)
                try updatedQueue.replaceWindow(with: page, centeredOn: currentQueueItemID)
            }
            guard let queuedItem = updatedQueue.move(direction) else {
                throw PlexAPIError.invalidPlayQueue
            }

            try await transition(
                to: queuedItem,
                queue: updatedQueue,
                completedCurrentItem: completedCurrentItem,
                startTimeOverride: (
                    updatedQueue.isCinemaPreplayQueue || direction == .previous
                ) ? 0 : nil,
                ticket: ticket
            )
        } catch is CancellationError {
            return
        } catch {
            if isCurrentSession(ticket) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func navigate(
        toPlayQueueItemID playQueueItemID: String,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async {
        guard !isQueueBusy, isCurrentSession(ticket),
              var updatedQueue = queue,
              updatedQueue.presentation.upcomingItems.contains(where: {
                  $0.playQueueItemID == playQueueItemID
              }),
              let queuedItem = updatedQueue.move(toPlayQueueItemID: playQueueItemID) else {
            return
        }

        isTransitioning = true
        isLoading = true
        updatePlaybackControlAvailability()
        defer {
            if isCurrentSession(ticket) {
                isLoading = false
                isTransitioning = false
                updatePlaybackControlAvailability()
            }
        }

        do {
            try await transition(
                to: queuedItem,
                queue: updatedQueue,
                completedCurrentItem: false,
                startTimeOverride: updatedQueue.isCinemaPreplayQueue ? 0 : nil,
                ticket: ticket
            )
        } catch is CancellationError {
            return
        } catch {
            if isCurrentSession(ticket) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func transition(
        to queuedItem: PlexMediaItem,
        queue updatedQueue: PlexPlaybackQueue?,
        completedCurrentItem: Bool,
        startTimeOverride: TimeInterval?,
        ticket: PlexPlaybackSessionEpoch.Ticket
    ) async throws {
        let nextItem = try await browserStore.refreshedPlayableDetails(for: queuedItem)
        try checkCurrentSession(ticket)
        let nextPlan = try await browserStore.playbackPlan(
            for: nextItem,
            source: presentation.queueSourcePreference?.source(for: nextItem),
            videoQuality: presentation.videoQuality,
            startTimeOverride: startTimeOverride
        )
        try checkCurrentSession(ticket)

        let completedTime = Int((playbackDuration ?? engine.position) * 1_000)
        await reportTimeline(
            state: .stopped,
            continuing: true,
            time: completedCurrentItem ? completedTime : nil,
            ticket: ticket
        )
        try checkCurrentSession(ticket)
        if completedCurrentItem, queue?.isCurrentCinemaPreplayItem != true {
            try await browserStore.markPlayedIfSupported(ratingKey: presentation.item.ratingKey)
            try checkCurrentSession(ticket)
        }

        queue = updatedQueue
        queueErrorMessage = nil
        replacePresentation(PlexPlaybackPresentation(
            item: nextItem,
            plan: nextPlan,
            queue: updatedQueue,
            videoQuality: presentation.videoQuality,
            serverIdentifier: presentation.serverIdentifier,
            queueSourcePreference: presentation.queueSourcePreference
        ))
        timelineCadence.reset()
        handledEndSessionIdentifier = nil
        clearNativeMediaSelectionAvailability()
        try await engine.load(plan: nextPlan)
        try checkCurrentSession(ticket)
        activateNowPlaying()
    }

    private var nowPlayingMetadata: PlexNowPlayingMetadata {
        let queuePresentation = queue?.presentation
        return PlexNowPlayingMetadata(
            item: presentation.item,
            duration: playbackDuration,
            elapsedTime: engine.position,
            playbackRate: engine.status == .playing ? Double(engine.player.rate) : 0,
            defaultPlaybackRate: Double(engine.playbackRate.rawValue),
            serverIdentifier: presentation.serverIdentifier,
            queuePosition: queuePresentation?.currentPosition,
            queueCount: queuePresentation?.totalCount
        )
    }

    private func updateServerManagedMediaSelectionControls() {
        coordinator.updateServerManagedMediaSelection(
            for: self,
            selection: serverManagedMediaSelection,
            canChange: canChangeMediaSelection
        )
    }


    private var nowPlayingLanguageOptions: PlexNowPlayingLanguageOptions {
        PlexNowPlayingLanguageOptions(
            selection: mediaSelection,
            nativeAvailability: nativeMediaSelectionState.availability
        )
    }

    private var canChangeLanguageOptions: Bool {
        canChangeMediaSelection
    }
}

private extension PlexPlaybackStatus {
    var label: String {
        switch self {
        case .idle: "Idle"
        case .preparing: "Preparing"
        case .playing: "Playing"
        case .paused: "Paused"
        case .buffering: "Buffering"
        case .ended: "Ended"
        case .failed: "Failed"
        }
    }
}
