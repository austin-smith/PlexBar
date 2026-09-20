import AppKit
import PlexClientKit
import SwiftUI

/// Native List navigation consumes Option–Arrow before SwiftUI's onKeyPress.
/// Scope interception to the popover window so the player keeps its own keys.
struct PlexQueueKeyboardShortcuts: NSViewRepresentable {
    let move: (PlexPlayQueueItemMoveDirection) -> Bool

    func makeNSView(context: Context) -> PlexQueueKeyboardView {
        let view = PlexQueueKeyboardView()
        view.move = move
        return view
    }

    func updateNSView(_ nsView: PlexQueueKeyboardView, context: Context) {
        nsView.move = move
    }

    static func dismantleNSView(_ nsView: PlexQueueKeyboardView, coordinator: ()) {
        nsView.stop()
    }
}

final class PlexQueueKeyboardView: NSView {
    var move: ((PlexPlayQueueItemMoveDirection) -> Bool)?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKeyDown(event) == true }
            return handled ? nil : event
        }
    }

    func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        // NSPopover can deliver keys through its owner even while its panel is key.
        guard let window, let eventWindow = event.window, window.isKeyWindow,
              eventWindow === window || eventWindow === window.parent,
              window.attachedSheet == nil, NSApp.modalWindow == nil,
              !(window.firstResponder is NSTextView),
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .option else {
            return false
        }
        let direction: PlexPlayQueueItemMoveDirection
        switch event.keyCode {
        case 126: direction = .up
        case 125: direction = .down
        default: return false
        }
        return move?(direction) == true
    }
}
