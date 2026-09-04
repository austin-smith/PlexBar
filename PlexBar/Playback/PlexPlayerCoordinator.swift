import Foundation
import Observation

struct PlexCurrentPlayback: Equatable, Sendable {
    let item: PlexMediaItem
    let serverIdentifier: String?

    init(presentation: PlexPlaybackPresentation) {
        item = presentation.item
        serverIdentifier = presentation.serverIdentifier?.nilIfBlank
    }

    func belongs(to serverIdentifier: String?) -> Bool {
        guard let ownServerIdentifier = self.serverIdentifier,
              let serverIdentifier = serverIdentifier?.nilIfBlank else {
            return false
        }
        return ownServerIdentifier == serverIdentifier
    }
}

@MainActor
@Observable
final class PlexPlayerCoordinator {
    var presentation: PlexPlaybackPresentation?
    private(set) var currentPlayback: PlexCurrentPlayback?
    private(set) var canGoPrevious = false
    private(set) var canGoNext = false
    private(set) var transportAction: PlexPlaybackTransportAction?
    private(set) var canStop = false
    private(set) var playbackStatus: PlexPlaybackStatus = .idle
    private(set) var canSeek = false
    private(set) var canChangePlaybackRate = false
    private(set) var playbackRate: PlexPlaybackRate = .normal
    private(set) var videoQualitySelection = PlexVideoQualitySelection(
        selectedQuality: .original,
        isVideo: false,
        canChange: false
    )
    private(set) var serverManagedMediaSelection = PlexServerManagedMediaSelection()
    private(set) var canChangeServerManagedMediaSelection = false
    private(set) var canChangeShuffle = false
    private(set) var isShuffled = false
    private(set) var canChangeRepeatMode = false
    private(set) var canRepeatAll = false
    private(set) var repeatMode: PlexPlaybackRepeatMode = .off
    private(set) var canAddItemsToQueue = false
    private(set) var isAddingToQueue = false

    @ObservationIgnored private var previousAction: (@MainActor () -> Void)?
    @ObservationIgnored private var nextAction: (@MainActor () -> Void)?
    @ObservationIgnored private var togglePlaybackAction: (@MainActor () -> Void)?
    @ObservationIgnored private var stopAction: (@MainActor () -> Void)?
    @ObservationIgnored private var seekAction: (@MainActor (TimeInterval) -> Void)?
    @ObservationIgnored private var playbackRateAction: (@MainActor (PlexPlaybackRate) -> Void)?
    @ObservationIgnored private var videoQualityAction: (@MainActor (PlexVideoQuality) -> Void)?
    @ObservationIgnored private var audioStreamAction: (@MainActor (Int) -> Void)?
    @ObservationIgnored private var subtitleStreamAction: (@MainActor (Int?) -> Void)?
    @ObservationIgnored private var shuffleAction: (@MainActor (Bool) -> Void)?
    @ObservationIgnored private var repeatModeAction: (@MainActor (PlexPlaybackRepeatMode) -> Void)?
    @ObservationIgnored private var activeSession: PlexPlayerSessionModel?
    @ObservationIgnored private let userInteractionStore: PlexUserInteractionStore
    @ObservationIgnored private let bandwidthRegistry: PlexPlaybackBandwidthRegistry

    init(
        userInteractionStore: PlexUserInteractionStore = PlexUserInteractionStore(),
        bandwidthRegistry: PlexPlaybackBandwidthRegistry = PlexPlaybackBandwidthRegistry()
    ) {
        self.userInteractionStore = userInteractionStore
        self.bandwidthRegistry = bandwidthRegistry
    }

    func present(_ presentation: PlexPlaybackPresentation) {
        if self.presentation?.id != presentation.id {
            stopActiveSession(deactivateNowPlaying: false)
            clearPlaybackControls()
        }
        self.presentation = presentation
        publishCurrentPlayback(presentation)
    }

    func clear() {
        stopActiveSession(deactivateNowPlaying: true)
        presentation = nil
        currentPlayback = nil
        clearPlaybackControls()
    }

    func session(
        for presentation: PlexPlaybackPresentation,
        browserStore: PlexBrowserStore,
        downloadsStore: PlexDownloadsStore? = nil
    ) -> PlexPlayerSessionModel {
        session(
            for: presentation,
            browserStore: browserStore,
            settingsStore: browserStore.connectionStore.settings,
            downloadsStore: downloadsStore
        )
    }

    func session(
        for presentation: PlexPlaybackPresentation,
        browserStore: PlexBrowserStore,
        settingsStore: PlexSettingsStore,
        downloadsStore: PlexDownloadsStore? = nil
    ) -> PlexPlayerSessionModel {
        if let activeSession {
            return activeSession
        }

        let session = PlexPlayerSessionModel(
            presentation: presentation,
            browserStore: browserStore,
            settingsStore: settingsStore,
            userInteractionStore: userInteractionStore,
            coordinator: self,
            downloadsStore: downloadsStore,
            bandwidthRegistry: bandwidthRegistry
        )
        activeSession = session
        return session
    }

    func close(_ session: PlexPlayerSessionModel) {
        guard activeSession === session else {
            session.stop(deactivateNowPlaying: false)
            return
        }

        activeSession = nil
        presentation = nil
        currentPlayback = nil
        clearPlaybackControls()
        session.stop()
    }

    func isActive(_ session: PlexPlayerSessionModel) -> Bool {
        activeSession === session
    }

    func updateCurrentPlayback(
        for session: PlexPlayerSessionModel,
        presentation: PlexPlaybackPresentation
    ) {
        guard isActive(session) else {
            return
        }
        publishCurrentPlayback(presentation)
    }

    func installNavigation(
        for session: PlexPlayerSessionModel,
        previous: @escaping @MainActor () -> Void,
        next: @escaping @MainActor () -> Void
    ) {
        guard isActive(session) else {
            return
        }
        installNavigation(previous: previous, next: next)
    }

    func updateNavigation(
        for session: PlexPlayerSessionModel,
        canGoPrevious: Bool,
        canGoNext: Bool
    ) {
        guard isActive(session) else {
            return
        }
        updateNavigation(canGoPrevious: canGoPrevious, canGoNext: canGoNext)
    }

    func clearNavigation(for session: PlexPlayerSessionModel) {
        guard isActive(session) else {
            return
        }
        clearNavigation()
    }

    func installTransport(
        for session: PlexPlayerSessionModel,
        status: PlexPlaybackStatus,
        canToggle: Bool,
        toggle: @escaping @MainActor () -> Void,
        stop: @escaping @MainActor () -> Void
    ) {
        guard isActive(session) else {
            return
        }
        installTransport(
            status: status,
            canToggle: canToggle,
            toggle: toggle,
            stop: stop
        )
    }

    func updateTransport(
        for session: PlexPlayerSessionModel,
        status: PlexPlaybackStatus,
        canToggle: Bool
    ) {
        guard isActive(session) else {
            return
        }
        updateTransport(status: status, canToggle: canToggle)
    }

    func clearTransport(for session: PlexPlayerSessionModel) {
        guard isActive(session) else {
            return
        }
        clearTransport()
    }

    func installSeeking(
        for session: PlexPlayerSessionModel,
        canSeek: Bool,
        action: @escaping @MainActor (TimeInterval) -> Void
    ) {
        guard isActive(session) else {
            return
        }
        installSeeking(canSeek: canSeek, action: action)
    }

    func updateSeeking(for session: PlexPlayerSessionModel, canSeek: Bool) {
        guard isActive(session) else {
            return
        }
        updateSeeking(canSeek: canSeek)
    }

    func clearSeeking(for session: PlexPlayerSessionModel) {
        guard isActive(session) else {
            return
        }
        clearSeeking()
    }

    func installPlaybackRate(
        for session: PlexPlayerSessionModel,
        playbackRate: PlexPlaybackRate,
        action: @escaping @MainActor (PlexPlaybackRate) -> Void
    ) {
        guard isActive(session) else {
            return
        }
        installPlaybackRate(playbackRate: playbackRate, action: action)
    }

    func updatePlaybackRate(
        for session: PlexPlayerSessionModel,
        playbackRate: PlexPlaybackRate
    ) {
        guard isActive(session) else {
            return
        }
        self.playbackRate = playbackRate
    }

    func clearPlaybackRate(for session: PlexPlayerSessionModel) {
        guard isActive(session) else {
            return
        }
        clearPlaybackRate()
    }

    func installVideoQuality(
        for session: PlexPlayerSessionModel,
        selection: PlexVideoQualitySelection,
        action: @escaping @MainActor (PlexVideoQuality) -> Void
    ) {
        guard isActive(session) else {
            return
        }
        installVideoQuality(selection: selection, action: action)
    }

    func updateVideoQuality(
        for session: PlexPlayerSessionModel,
        selection: PlexVideoQualitySelection
    ) {
        guard isActive(session) else {
            return
        }
        videoQualitySelection = selection
    }

    func clearVideoQuality(for session: PlexPlayerSessionModel) {
        guard isActive(session) else {
            return
        }
        clearVideoQuality()
    }

    func installServerManagedMediaSelection(
        for session: PlexPlayerSessionModel,
        selection: PlexServerManagedMediaSelection,
        canChange: Bool,
        selectAudioStream: @escaping @MainActor (Int) -> Void,
        selectSubtitleStream: @escaping @MainActor (Int?) -> Void
    ) {
        guard isActive(session) else {
            return
        }
        installServerManagedMediaSelection(
            selection: selection,
            canChange: canChange,
            selectAudioStream: selectAudioStream,
            selectSubtitleStream: selectSubtitleStream
        )
    }

    func updateServerManagedMediaSelection(
        for session: PlexPlayerSessionModel,
        selection: PlexServerManagedMediaSelection,
        canChange: Bool
    ) {
        guard isActive(session) else {
            return
        }
        updateServerManagedMediaSelection(selection: selection, canChange: canChange)
    }

    func clearServerManagedMediaSelection(for session: PlexPlayerSessionModel) {
        guard isActive(session) else {
            return
        }
        clearServerManagedMediaSelection()
    }

    func clearPlaybackControls(for session: PlexPlayerSessionModel) {
        guard isActive(session) else {
            return
        }
        clearPlaybackControls()
    }

    func installShuffle(
        for session: PlexPlayerSessionModel,
        isShuffled: Bool,
        canChange: Bool,
        action: @escaping @MainActor (Bool) -> Void
    ) {
        guard isActive(session) else {
            return
        }
        installShuffle(isShuffled: isShuffled, canChange: canChange, action: action)
    }

    func updateShuffle(
        for session: PlexPlayerSessionModel,
        isShuffled: Bool,
        canChange: Bool
    ) {
        guard isActive(session) else {
            return
        }
        updateShuffle(isShuffled: isShuffled, canChange: canChange)
    }

    func clearShuffle(for session: PlexPlayerSessionModel) {
        guard isActive(session) else {
            return
        }
        clearShuffle()
    }

    func installRepeatMode(
        for session: PlexPlayerSessionModel,
        repeatMode: PlexPlaybackRepeatMode,
        canRepeatAll: Bool,
        action: @escaping @MainActor (PlexPlaybackRepeatMode) -> Void
    ) {
        guard isActive(session) else {
            return
        }
        installRepeatMode(
            repeatMode: repeatMode,
            canRepeatAll: canRepeatAll,
            action: action
        )
    }

    func updateRepeatMode(
        for session: PlexPlayerSessionModel,
        repeatMode: PlexPlaybackRepeatMode,
        canRepeatAll: Bool
    ) {
        guard isActive(session) else {
            return
        }
        updateRepeatMode(repeatMode: repeatMode, canRepeatAll: canRepeatAll)
    }

    func clearRepeatMode(for session: PlexPlayerSessionModel) {
        guard isActive(session) else {
            return
        }
        clearRepeatMode()
    }

    func updateQueueInsertion(
        for session: PlexPlayerSessionModel,
        canAdd: Bool,
        isAdding: Bool
    ) {
        guard isActive(session) else {
            return
        }
        canAddItemsToQueue = canAdd
        isAddingToQueue = isAdding
    }

    func canAddToQueue(_ item: PlexMediaItem) -> Bool {
        canAddItemsToQueue && activeSession?.canAddToQueue(item) == true
    }

    func addToQueue(
        _ item: PlexMediaItem,
        insertion: PlexPlayQueueInsertion
    ) async throws {
        guard canAddToQueue(item), let activeSession else {
            throw PlexAPIError.invalidPlayQueue
        }
        try await activeSession.addToQueue(item, insertion: insertion)
    }

    func installNavigation(
        previous: @escaping @MainActor () -> Void,
        next: @escaping @MainActor () -> Void
    ) {
        previousAction = previous
        nextAction = next
    }

    func updateNavigation(canGoPrevious: Bool, canGoNext: Bool) {
        self.canGoPrevious = canGoPrevious
        self.canGoNext = canGoNext
    }

    func goPrevious() {
        guard canGoPrevious else {
            return
        }
        previousAction?()
    }

    func goNext() {
        guard canGoNext else {
            return
        }
        nextAction?()
    }

    func togglePlayback() {
        guard transportAction != nil else {
            return
        }
        togglePlaybackAction?()
    }

    func stopPlayback() {
        guard canStop else {
            return
        }
        stopAction?()
    }

    func skipBackward() {
        skip(.backward)
    }

    func skipForward() {
        skip(.forward)
    }

    func selectPlaybackRate(_ playbackRate: PlexPlaybackRate) {
        guard canChangePlaybackRate else {
            return
        }
        playbackRateAction?(playbackRate)
    }

    func selectVideoQuality(_ videoQuality: PlexVideoQuality) {
        guard videoQualitySelection.canSelect(videoQuality) else {
            return
        }
        videoQualityAction?(videoQuality)
    }

    func selectAudioStream(_ streamID: Int) {
        guard canChangeServerManagedMediaSelection,
              serverManagedMediaSelection.canSelectAudioStream(streamID) else {
            return
        }
        audioStreamAction?(streamID)
    }

    func selectSubtitleStream(_ streamID: Int?) {
        guard canChangeServerManagedMediaSelection,
              serverManagedMediaSelection.canSelectSubtitleStream(streamID) else {
            return
        }
        subtitleStreamAction?(streamID)
    }

    func setShuffled(_ isShuffled: Bool) {
        guard canChangeShuffle, self.isShuffled != isShuffled else {
            return
        }
        shuffleAction?(isShuffled)
    }

    func selectRepeatMode(_ repeatMode: PlexPlaybackRepeatMode) {
        guard canChangeRepeatMode,
              repeatMode != self.repeatMode,
              repeatMode != .all || canRepeatAll else {
            return
        }
        repeatModeAction?(repeatMode)
    }

    func clearNavigation() {
        canGoPrevious = false
        canGoNext = false
        previousAction = nil
        nextAction = nil
    }

    func installTransport(
        status: PlexPlaybackStatus,
        canToggle: Bool = true,
        toggle: @escaping @MainActor () -> Void,
        stop: @escaping @MainActor () -> Void
    ) {
        togglePlaybackAction = toggle
        stopAction = stop
        canStop = true
        updateTransport(status: status, canToggle: canToggle)
    }

    func updateTransport(status: PlexPlaybackStatus, canToggle: Bool = true) {
        playbackStatus = status
        transportAction = canToggle ? PlexPlaybackTransportAction(status: status) : nil
    }

    func clearTransport() {
        playbackStatus = .idle
        transportAction = nil
        canStop = false
        togglePlaybackAction = nil
        stopAction = nil
    }

    func installSeeking(
        canSeek: Bool,
        action: @escaping @MainActor (TimeInterval) -> Void
    ) {
        self.canSeek = canSeek
        seekAction = action
    }

    func updateSeeking(canSeek: Bool) {
        self.canSeek = canSeek
    }

    func clearSeeking() {
        canSeek = false
        seekAction = nil
    }

    func installPlaybackRate(
        playbackRate: PlexPlaybackRate,
        action: @escaping @MainActor (PlexPlaybackRate) -> Void
    ) {
        self.playbackRate = playbackRate
        playbackRateAction = action
        canChangePlaybackRate = true
    }

    func clearPlaybackRate() {
        playbackRate = .normal
        playbackRateAction = nil
        canChangePlaybackRate = false
    }

    func installVideoQuality(
        selection: PlexVideoQualitySelection,
        action: @escaping @MainActor (PlexVideoQuality) -> Void
    ) {
        videoQualitySelection = selection
        videoQualityAction = action
    }

    func clearVideoQuality() {
        videoQualitySelection = PlexVideoQualitySelection(
            selectedQuality: .original,
            isVideo: false,
            canChange: false
        )
        videoQualityAction = nil
    }

    func installServerManagedMediaSelection(
        selection: PlexServerManagedMediaSelection,
        canChange: Bool,
        selectAudioStream: @escaping @MainActor (Int) -> Void,
        selectSubtitleStream: @escaping @MainActor (Int?) -> Void
    ) {
        audioStreamAction = selectAudioStream
        subtitleStreamAction = selectSubtitleStream
        updateServerManagedMediaSelection(selection: selection, canChange: canChange)
    }

    func updateServerManagedMediaSelection(
        selection: PlexServerManagedMediaSelection,
        canChange: Bool
    ) {
        serverManagedMediaSelection = selection
        canChangeServerManagedMediaSelection = canChange && selection.hasChoices
    }

    func clearServerManagedMediaSelection() {
        serverManagedMediaSelection = PlexServerManagedMediaSelection()
        canChangeServerManagedMediaSelection = false
        audioStreamAction = nil
        subtitleStreamAction = nil
    }

    func installShuffle(
        isShuffled: Bool,
        canChange: Bool,
        action: @escaping @MainActor (Bool) -> Void
    ) {
        self.isShuffled = isShuffled
        canChangeShuffle = canChange
        shuffleAction = action
    }

    func updateShuffle(isShuffled: Bool, canChange: Bool) {
        self.isShuffled = isShuffled
        canChangeShuffle = canChange
    }

    func clearShuffle() {
        isShuffled = false
        canChangeShuffle = false
        shuffleAction = nil
    }

    func installRepeatMode(
        repeatMode: PlexPlaybackRepeatMode,
        canRepeatAll: Bool,
        action: @escaping @MainActor (PlexPlaybackRepeatMode) -> Void
    ) {
        self.repeatMode = repeatMode
        self.canRepeatAll = canRepeatAll
        repeatModeAction = action
        canChangeRepeatMode = true
    }

    func updateRepeatMode(
        repeatMode: PlexPlaybackRepeatMode,
        canRepeatAll: Bool
    ) {
        self.repeatMode = repeatMode
        self.canRepeatAll = canRepeatAll
    }

    func clearRepeatMode() {
        repeatMode = .off
        canRepeatAll = false
        canChangeRepeatMode = false
        repeatModeAction = nil
    }

    func clearQueueInsertion() {
        canAddItemsToQueue = false
        isAddingToQueue = false
    }

    private func clearPlaybackControls() {
        clearTransport()
        clearNavigation()
        clearSeeking()
        clearPlaybackRate()
        clearVideoQuality()
        clearServerManagedMediaSelection()
        clearShuffle()
        clearRepeatMode()
        clearQueueInsertion()
    }

    private func stopActiveSession(deactivateNowPlaying: Bool) {
        guard let activeSession else {
            return
        }

        self.activeSession = nil
        activeSession.stop(deactivateNowPlaying: deactivateNowPlaying)
    }

    private func publishCurrentPlayback(_ presentation: PlexPlaybackPresentation) {
        let currentPlayback = PlexCurrentPlayback(presentation: presentation)
        guard self.currentPlayback != currentPlayback else {
            return
        }
        self.currentPlayback = currentPlayback
    }

    private func skip(_ direction: PlexPlaybackSkipDirection) {
        guard canSeek,
              let offset = direction.offset(for: PlexPlaybackSeek.skipInterval) else {
            return
        }
        seekAction?(offset)
    }
}
