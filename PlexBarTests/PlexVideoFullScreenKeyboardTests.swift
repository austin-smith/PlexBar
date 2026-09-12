import AppKit
import Testing
@testable import PlexBar

@MainActor
struct PlexVideoFullScreenKeyboardTests {
    @Test func fTogglesVideoAndEscapeOnlyExitsFullScreen() {
        #expect(action("f", fullScreen: false) == .enter)
        #expect(action("f", fullScreen: true) == .exit)
        #expect(action("\u{1b}", fullScreen: true) == .exit)
        #expect(action("\u{1b}", fullScreen: false) == nil)
        #expect(action(" ", fullScreen: false) == nil)
    }

    @Test func typingAndSystemShortcutsAreNotIntercepted() {
        for fullScreen in [false, true] {
            #expect(action("f", fullScreen: fullScreen, editing: true) == nil)
            #expect(action("\u{1b}", fullScreen: fullScreen, editing: true) == nil)
            for modifiers: NSEvent.ModifierFlags in [
                .command, [.control, .command], .function, .control, .option, .shift,
            ] {
                #expect(action("f", fullScreen: fullScreen, modifiers: modifiers) == nil)
            }
        }
        #expect(action("F", fullScreen: false, modifiers: .capsLock) == .enter)
    }

    @Test func playbackSurvivesBothFullScreenTransitions() {
        let lifecycle = PlexPlayerPresentationLifecycle()
        lifecycle.willEnterFullScreen()
        #expect(lifecycle.isFullScreenTransitioning)
        #expect(lifecycle.keepsPlaybackAliveWhenViewDisappears)
        lifecycle.didEnterFullScreen()
        #expect(!lifecycle.isFullScreenTransitioning)
        #expect(lifecycle.isFullScreenActive)
        lifecycle.willExitFullScreen()
        #expect(lifecycle.isFullScreenTransitioning)
        #expect(lifecycle.keepsPlaybackAliveWhenViewDisappears)
        lifecycle.didExitFullScreen()
        #expect(!lifecycle.isFullScreenTransitioning)
        #expect(!lifecycle.isFullScreenActive)
    }

    private func action(
        _ characters: String,
        fullScreen: Bool,
        editing: Bool = false,
        modifiers: NSEvent.ModifierFlags = []
    ) -> PlexVideoFullScreenKeyboardHandler.Action? {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: characters == "\u{1b}" ? 53 : 3
        )!
        return PlexVideoFullScreenKeyboardHandler.action(
            for: event,
            isFullScreenActive: fullScreen,
            isEditingText: editing
        )
    }
}
