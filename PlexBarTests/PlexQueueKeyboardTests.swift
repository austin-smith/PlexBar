import AppKit
import Testing
@testable import PlexBar

@MainActor
struct PlexQueueKeyboardTests {
    @Test func reorderKeysStayInsideTheQueueWindowAndYieldToEditing() {
        let view = PlexQueueKeyboardView()
        let window = QueueTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let otherWindow = QueueTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let ownerWindow = QueueTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        ownerWindow.addChildWindow(window, ordered: .above)
        window.contentView = view
        var moves: [String] = []
        view.move = { direction in
            moves.append(direction == .up ? "up" : "down")
            return true
        }
        defer {
            view.stop()
            ownerWindow.removeChildWindow(window)
            window.orderOut(nil)
            otherWindow.orderOut(nil)
            ownerWindow.orderOut(nil)
        }

        func event(_ key: UInt16, modifiers: NSEvent.ModifierFlags = .option, target: NSWindow? = nil) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: (target ?? window).windowNumber, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key
            )!
        }

        #expect(view.handleKeyDown(event(126)))
        #expect(view.handleKeyDown(event(125)))
        #expect(view.handleKeyDown(event(125, target: ownerWindow)))
        #expect(!view.handleKeyDown(event(125, modifiers: [])))
        #expect(!view.handleKeyDown(event(125, modifiers: [.command, .option])))
        #expect(!view.handleKeyDown(event(123)))
        #expect(!view.handleKeyDown(event(125, target: otherWindow)))
        window.hasKeyFocus = false
        #expect(!view.handleKeyDown(event(125)))
        window.hasKeyFocus = true

        let editor = NSTextView()
        view.addSubview(editor)
        window.makeFirstResponder(editor)
        #expect(!view.handleKeyDown(event(125)))
        #expect(moves == ["up", "down", "down"])

        window.makeFirstResponder(nil)
        view.move = { _ in false }
        #expect(!view.handleKeyDown(event(125)))
    }
}

private final class QueueTestWindow: NSWindow {
    var hasKeyFocus = true
    override var isKeyWindow: Bool { hasKeyFocus }
}
