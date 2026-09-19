import AppKit
import Testing
@testable import PlexBar

@MainActor
struct PlexPlayerTransportKeyboardTests {
    @Test func routesOnceOnlyInsideThePlayerWindowAndYieldsToEditing() {
        let view = PlexPlayerVideoNSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let window = PlaybackTestWindow(
            contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = view
        let coordinator = PlexPlayerCoordinator()
        let state = PlexPlayerControlsState()
        var offsets: [Double] = []
        var nextCount = 0
        coordinator.installSeeking(canSeek: true) { offsets.append($0) }
        coordinator.installNavigation(previous: {}, next: { nextCount += 1 })
        coordinator.updateNavigation(canGoPrevious: false, canGoNext: true)
        let handler = PlexPlayerTransportKeyboardHandler(
            playerView: view,
            lifecycle: PlexPlayerPresentationLifecycle(),
            coordinator: coordinator,
            controlsState: state,
            toggleFullScreen: {}
        )
        defer { handler.stop(); state.stop(); window.orderOut(nil) }
        window.makeFirstResponder(view)
        #expect(window.isKeyWindow)

        func event(_ key: UInt16, modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: key
            )!
        }
        #expect(handler.handleKeyDown(event(124)))
        #expect(handler.handleKeyDown(event(124, repeatKey: true)))
        #expect(offsets == [10, 10])
        #expect(handler.handleKeyDown(event(124, modifiers: .command)))
        #expect(handler.handleKeyDown(event(124, modifiers: .command, repeatKey: true)))
        #expect(nextCount == 1)

        window.hasKeyFocus = false
        #expect(!handler.handleKeyDown(event(123)))
        window.hasKeyFocus = true
        state.isMenuTracking = true
        #expect(!handler.handleKeyDown(event(123)))
        state.isMenuTracking = false
        state.isPopoverPresented = true
        #expect(!handler.handleKeyDown(event(123)))
        #expect(!handler.handleKeyDown(event(124, modifiers: .command)))
        state.isPopoverPresented = false
        handler.isBlocked = true
        #expect(!handler.handleKeyDown(event(123)))
        handler.isBlocked = false
        let textView = NSTextView(frame: view.bounds)
        view.addSubview(textView)
        window.makeFirstResponder(textView)
        #expect(!handler.handleKeyDown(event(123)))
        #expect(!handler.handleKeyDown(event(124, modifiers: .command)))
        #expect(offsets == [10, 10])
        #expect(nextCount == 1)
    }

    @Test func arrowsSeekAndCommandArrowsNavigateTheQueue() {
        #expect(action(123) == .skipBackward)
        #expect(action(124) == .skipForward)
        #expect(action(123, modifiers: .command) == .previous)
        #expect(action(124, modifiers: .command) == .next)
        #expect(action(49) == .togglePlayback)
        // Real macOS arrow events carry these flags even without modifiers.
        #expect(action(123, modifiers: [.numericPad, .function, .capsLock]) == .skipBackward)
        #expect(action(124, modifiers: [.command, .numericPad, .function]) == .next)
    }

    @Test func textEditingAndFocusedControlsKeepTheirKeys() {
        for key: UInt16 in [123, 124, 49] {
            #expect(action(key, focusedControl: true) == nil)
            #expect(action(key, modifiers: .command, focusedControl: true) == nil)
            for modifiers: NSEvent.ModifierFlags in [.shift, .option, .control, [.command, .shift]] {
                #expect(action(key, modifiers: modifiers) == nil)
            }
        }
        #expect(action(125) == nil)
        #expect(action(126) == nil)
        #expect(action(3) == nil)
        #expect(action(49, modifiers: .function) == nil)
        #expect(PlexPlayerTransportKeyboardHandler.hasFocusedControl(NSTextView()))
        #expect(PlexPlayerTransportKeyboardHandler.hasFocusedControl(NSSlider()))
        #expect(PlexPlayerTransportKeyboardHandler.hasFocusedControl(NSButton()))
        #expect(!PlexPlayerTransportKeyboardHandler.hasFocusedControl(NSView()))
    }

    private func action(
        _ keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        focusedControl: Bool = false
    ) -> PlexPlayerTransportKeyboardHandler.Action? {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode
        )!
        return PlexPlayerTransportKeyboardHandler.action(for: event, hasFocusedControl: focusedControl)
    }
}

@MainActor
private final class PlaybackTestWindow: NSWindow {
    // Exercise routing without stealing focus from the desktop or another test.
    var hasKeyFocus = true
    override var isKeyWindow: Bool { hasKeyFocus }
}
