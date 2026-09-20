@testable import PlexClientKit
import AVFoundation
import Testing
@testable import PlexBar

@MainActor
struct PlexPlayerControlsTests {
    @Test func switchingPopoversKeepsTheAnchorVisibleAndIgnoresStaleDismissal() async throws {
        let state = PlexPlayerControlsState(inactivityDelay: .milliseconds(40))
        defer { state.stop() }

        state.togglePopover(.volume)
        state.togglePopover(.upNext)
        // Native popover dismissal can arrive after the other button is clicked.
        state.dismissPopover(.volume)
        #expect(state.presentedPopover == .upNext)
        try await waitForIdle(state)
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))

        state.togglePopover(.upNext)
        #expect(!state.isPopoverPresented)
        try await waitForIdle(state)
        #expect(!state.isVisible(status: .playing, voiceOverEnabled: false))

        state.togglePopover(.upNext)
        state.togglePopover(.volume)
        state.dismissPopover(.upNext)
        #expect(state.presentedPopover == .volume)
        state.dismissPopover()
        #expect(!state.isPopoverPresented)
    }

    @Test func controlsStayAvailableDuringInteractionAndPausedPlayback() {
        let state = PlexPlayerControlsState()
        state.isPointerActive = false
        #expect(!state.isVisible(status: .playing, voiceOverEnabled: false))
        #expect(state.isVisible(status: .paused, voiceOverEnabled: false))
        #expect(state.isVisible(status: .buffering, voiceOverEnabled: false))
        #expect(state.isVisible(status: .playing, voiceOverEnabled: true))
        state.scrub.begin(at: 10)
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.scrub.reset()
        state.keyboardActivity(isNavigation: true)
        state.isPointerActive = false
        state.isTimelineFocused = true
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.isTimelineFocused = false
        state.hasKeyboardFocus = true
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.hasKeyboardFocus = false
        state.isMenuTracking = true
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.isMenuTracking = false
        state.togglePopover(.volume)
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.stop()
    }

    @Test func stationaryPointerAndIncidentalFocusExpireAfterActivity() async throws {
        let state = PlexPlayerControlsState(inactivityDelay: .milliseconds(40))
        defer { state.stop() }
        state.hasKeyboardFocus = true
        state.isTimelineFocused = true
        state.pointerActivity()
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        try await waitForIdle(state)
        #expect(!state.isVisible(status: .playing, voiceOverEnabled: false))
        state.pointerActivity()
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
    }

    @Test func tabFocusStaysVisibleUntilTheUserReturnsToPointerInput() async throws {
        let state = PlexPlayerControlsState(inactivityDelay: .milliseconds(40))
        defer { state.stop() }
        state.keyboardActivity(isNavigation: true)
        state.hasKeyboardFocus = true
        try await waitForIdle(state)
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.pointerActivity()
        try await waitForIdle(state)
        #expect(!state.isVisible(status: .playing, voiceOverEnabled: false))
        state.keyboardActivity(isNavigation: false)
        try await waitForIdle(state)
        #expect(!state.isVisible(status: .playing, voiceOverEnabled: false))
    }

    @Test func finishingInteractionsAllowsInactivityToHideControls() async throws {
        let state = PlexPlayerControlsState(inactivityDelay: .milliseconds(40))
        defer { state.stop() }
        state.scrub.begin(at: 10)
        state.pointerActivity()
        try await waitForIdle(state)
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        _ = state.scrub.finish(at: 20)
        state.isMenuTracking = true
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.isMenuTracking = false
        state.togglePopover(.volume)
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.dismissPopover()
        state.reveal()
        try await waitForIdle(state)
        #expect(!state.isVisible(status: .playing, voiceOverEnabled: false))
    }

    @Test func newActivityCancelsTheOldDeadline() async throws {
        let state = PlexPlayerControlsState(inactivityDelay: .milliseconds(150))
        defer { state.stop() }
        state.pointerActivity()
        try await Task.sleep(for: .milliseconds(100))
        state.pointerActivity()
        try await Task.sleep(for: .milliseconds(80))
        #expect(state.isPointerActive)
        try await waitForIdle(state)
        #expect(!state.isPointerActive)
    }

    private func waitForIdle(_ state: PlexPlayerControlsState) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while state.isPointerActive, .now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!state.isPointerActive)
    }

    @Test func timelineDisplaysLongMediaAndRejectsIndefiniteDurations() {
        #expect(PlexPlayerTimeDisplay.string(0) == "0:00")
        #expect(PlexPlayerTimeDisplay.string(69.9) == "1:09")
        #expect(PlexPlayerTimeDisplay.string(3_661) == "1:01:01")
        #expect(PlexPlayerTimeDisplay.string(.nan) == "--:--")
        #expect(PlexPlayerTimeDisplay.string(.infinity) == "--:--")
        #expect(PlexPlayerTimeDisplay.string(-1) == "--:--")
    }

    @Test func videoSurfaceUsesTheNativePlayerLayerAndPreservesHDRPolicy() {
        let view = PlexPlayerVideoNSView()
        #expect(view.layer === view.playerLayer)
        #expect(PlexVideoDisplayDynamicRange.automatic.layerDynamicRange == .automatic)
        #expect(PlexVideoDisplayDynamicRange.standard.layerDynamicRange == .standard)
        #expect(PlexVideoDisplayDynamicRange.constrainedHigh.layerDynamicRange == .constrainedHigh)
        #expect(PlexVideoDisplayDynamicRange.high.layerDynamicRange == .high)
    }
}
