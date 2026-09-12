import AppKit
import AVKit
import OSLog

@MainActor
final class PlexVideoFullScreenKeyboardHandler {
    enum Action {
        case enter
        case exit

        var selector: Selector {
            // AVKit exposes the button and delegate callbacks, but these actions
            // are undocumented. Keep these selectors isolated from playback logic.
            switch self {
            case .enter: NSSelectorFromString("enterFullScreen:")
            case .exit: NSSelectorFromString("exitFullScreen:")
            }
        }
    }

    private weak var playerView: AVPlayerView?
    private let lifecycle: PlexPlayerPresentationLifecycle
    private var eventMonitor: Any?
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "VideoFullScreen")

    init(playerView: AVPlayerView, lifecycle: PlexPlayerPresentationLifecycle) {
        self.playerView = playerView
        self.lifecycle = lifecycle
    }

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleKeyDown(event) == nil
            }
            return handled ? nil : event
        }
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let playerView,
              playerView.showsFullScreenToggleButton,
              playerView.player?.currentItem?.status == .readyToPlay,
              let window = event.window,
              window.isKeyWindow,
              window.attachedSheet == nil,
              NSApp.modalWindow == nil,
              !lifecycle.isPictureInPictureActive else {
            return event
        }

        // AVKit leaves the original AVPlayerView in its host window and presents
        // the video in a separate fullscreen window owned by the same app.
        guard window === playerView.window
                || (lifecycle.isFullScreenActive && window.styleMask.contains(.fullScreen)) else {
            return event
        }

        let isEditingText = (window.firstResponder as? NSTextView)?.isEditable == true
        guard let action = Self.action(
            for: event,
            isFullScreenActive: lifecycle.isFullScreenActive,
            isEditingText: isEditingText
        ) else {
            return event
        }

        // Consume repeats and presses during animation without starting a second
        // transition or allowing Escape to invoke Back to Library.
        guard !event.isARepeat, !lifecycle.isFullScreenTransitioning else { return nil }
        guard playerView.responds(to: action.selector) else {
            logger.error("AVKit does not support the video fullscreen action: \(NSStringFromSelector(action.selector), privacy: .public)")
            NSSound.beep()
            return nil
        }
        playerView.perform(action.selector, with: nil)
        return nil
    }

    static func action(
        for event: NSEvent,
        isFullScreenActive: Bool,
        isEditingText: Bool
    ) -> Action? {
        guard !isEditingText,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock).isEmpty else { return nil }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "f":
            return isFullScreenActive ? .exit : .enter
        case "\u{1b}" where isFullScreenActive:
            return .exit
        default:
            return nil
        }
    }
}
