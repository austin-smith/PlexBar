@testable import PlexClientKit
import AVFoundation
import Testing
@testable import PlexBar

@MainActor
struct PlexPlayerControlsTests {
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
        state.isTimelineFocused = true
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.isTimelineFocused = false
        state.hasKeyboardFocus = true
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.hasKeyboardFocus = false
        state.isHoveringControls = true
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.isHoveringControls = false
        state.isMenuTracking = true
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
        state.isMenuTracking = false
        state.isPopoverPresented = true
        #expect(state.isVisible(status: .playing, voiceOverEnabled: false))
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
