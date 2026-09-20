import AppKit
import Testing
@testable import PlexBar

@MainActor
struct PlexVideoFullScreenKeyboardTests {
    @Test func fTogglesVideoAndEscapeOnlyExitsFullScreen() {
        #expect(action("f", fullScreen: false) == .enterFullScreen)
        #expect(action("f", fullScreen: true) == .exitFullScreen)
        #expect(action("\u{1b}", fullScreen: true) == .exitFullScreen)
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
        #expect(action("F", fullScreen: false, modifiers: .capsLock) == .enterFullScreen)
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

    @Test func playerWindowAppearanceRestoresWhenReturningToTheLibrary() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = false
        let presentation = PlexPlayerPresentationController()
        presentation.attach(window: window)
        #expect(window.toolbarStyle == .unifiedCompact)
        #expect(window.titlebarAppearsTransparent)
        // Reattaching the same view must not overwrite the saved library style.
        presentation.attach(window: window)
        presentation.attach(window: nil)
        #expect(window.toolbarStyle == .unified)
        #expect(!window.titlebarAppearsTransparent)
        presentation.attach(window: window)
        presentation.detach()
        #expect(window.toolbarStyle == .unified)
        #expect(!window.titlebarAppearsTransparent)
        window.orderOut(nil)
    }

    private func action(
        _ characters: String,
        fullScreen: Bool,
        editing: Bool = false,
        modifiers: NSEvent.ModifierFlags = []
    ) -> PlexPlayerTransportKeyboardHandler.Action? {
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
        return PlexPlayerTransportKeyboardHandler.action(
            for: event,
            hasFocusedControl: editing,
            isFullScreenActive: fullScreen
        )
    }
}
