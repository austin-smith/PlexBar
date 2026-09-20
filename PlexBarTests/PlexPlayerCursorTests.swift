import AppKit
import Testing
@testable import PlexBar

@MainActor
struct PlexPlayerCursorTests {
    @Test func cursorRestoresWhenVisibilityOrWindowContextChanges() {
        let view = PlexPlayerVideoNSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let window = CursorTestWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.acceptsMouseMovedEvents = false
        var changes: [Bool] = []
        view.setCursorHiddenUntilMouseMoves = { changes.append($0) }
        window.contentView = view
        #expect(window.acceptsMouseMovedEvents)
        defer { view.stopPointerMonitoring(); window.orderOut(nil) }
        view.isCursorHidingAllowed = true
        view.updateCursorVisibility(applicationIsActive: true)
        #expect(view.isCursorHidden)
        #expect(changes.last == true)
        let hiddenChangeCount = changes.count
        view.updateCursorVisibility(applicationIsActive: true)
        #expect(changes.count == hiddenChangeCount)

        // Paused playback, overlays, VoiceOver, and PiP all revoke this permission.
        view.isCursorHidingAllowed = false
        #expect(!view.isCursorHidden)
        #expect(changes.last == false)
        view.isCursorHidingAllowed = true
        view.updateCursorVisibility(applicationIsActive: true)
        window.pointerLocation = NSPoint(x: 700, y: 100)
        view.updateCursorVisibility(applicationIsActive: true)
        #expect(!view.isCursorHidden)

        window.pointerLocation = NSPoint(x: 100, y: 100)
        view.updateCursorVisibility(applicationIsActive: true)
        #expect(view.isCursorHidden)
        view.updateCursorVisibility(applicationIsActive: false)
        #expect(!view.isCursorHidden)
        window.hasKeyFocus = false
        view.updateCursorVisibility(applicationIsActive: true)
        #expect(!view.isCursorHidden)
        window.hasKeyFocus = true
        view.updateCursorVisibility(applicationIsActive: true)
        #expect(view.isCursorHidden)
        view.stopPointerMonitoring()
        #expect(!window.acceptsMouseMovedEvents)
        #expect(!view.isCursorHidden)
        #expect(changes.last == false)
    }

    @Test func fullscreenAndActivationNotificationsRestoreCursorAndRevealControls() {
        let view = PlexPlayerVideoNSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let window = CursorTestWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        let state = PlexPlayerControlsState()
        view.controls = state
        view.setCursorHiddenUntilMouseMoves = { _ in }
        window.contentView = view
        defer { view.stopPointerMonitoring(); state.stop(); window.orderOut(nil) }
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification,
                     NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification,
                     NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification] {
            state.isPointerActive = false
            view.isCursorHidingAllowed = true
            view.updateCursorVisibility(applicationIsActive: true)
            #expect(view.isCursorHidden)
            NotificationCenter.default.post(name: name, object: window)
            #expect(!view.isCursorHidden)
            #expect(state.isPointerActive)
        }
        view.updateCursorVisibility(applicationIsActive: true)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(!view.isCursorHidden)
    }

    @Test func pointerActivityCoversOverlaidControlsButStaysInsideThePlayer() {
        let view = PlexPlayerVideoNSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let window = CursorTestWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        let state = PlexPlayerControlsState()
        view.controls = state
        view.setCursorHiddenUntilMouseMoves = { _ in }
        window.contentView = view
        let overlay = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 140))
        view.addSubview(overlay)
        defer { view.stopPointerMonitoring(); state.stop(); window.orderOut(nil) }
        func move(_ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 0, pressure: 0)!
        }
        state.keyboardActivity(isNavigation: true)
        state.isPointerActive = false
        view.handlePointerEvent(move(NSPoint(x: 100, y: 100)))
        #expect(state.isPointerActive)
        #expect(!state.isKeyboardNavigating)
        state.isPointerActive = false
        view.handlePointerEvent(move(NSPoint(x: 700, y: 100)))
        #expect(!state.isPointerActive)
        window.hasKeyFocus = false
        view.handlePointerEvent(move(NSPoint(x: 100, y: 100)))
        #expect(!state.isPointerActive)
    }
}

@MainActor
private final class CursorTestWindow: NSWindow {
    var hasKeyFocus = true
    var pointerLocation = NSPoint(x: 100, y: 100)
    override var isKeyWindow: Bool { hasKeyFocus }
    override var isVisible: Bool { true }
    override var mouseLocationOutsideOfEventStream: NSPoint { pointerLocation }
}
