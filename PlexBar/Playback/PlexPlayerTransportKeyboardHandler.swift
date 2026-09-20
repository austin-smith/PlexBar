import AppKit
import AVKit

/// Player shortcuts are scoped to its window and yield to focused controls.
@MainActor
final class PlexPlayerTransportKeyboardHandler {
    enum Action: Equatable {
        case togglePlayback, skipBackward, skipForward, previous, next
        case enterFullScreen, exitFullScreen, cancelScrub
    }

    private weak var playerView: NSView?
    private let lifecycle: PlexPlayerPresentationLifecycle
    private let coordinator: PlexPlayerCoordinator
    private let controlsState: PlexPlayerControlsState
    private let toggleFullScreen: () -> Void
    private var eventMonitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var trackingMenus: Set<ObjectIdentifier> = []
    var isBlocked = false
    var allowsFullScreen = true

    init(
        playerView: NSView,
        lifecycle: PlexPlayerPresentationLifecycle,
        coordinator: PlexPlayerCoordinator,
        controlsState: PlexPlayerControlsState,
        toggleFullScreen: @escaping () -> Void
    ) {
        self.playerView = playerView
        self.lifecycle = lifecycle
        self.coordinator = coordinator
        self.controlsState = controlsState
        self.toggleFullScreen = toggleFullScreen
    }

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKeyDown(event) == true }
            return handled ? nil : event
        }
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            menuObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                guard let menu = notification.object as? NSMenu else { return }
                let id = ObjectIdentifier(menu)
                let isBeginning = notification.name == NSMenu.didBeginTrackingNotification
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if isBeginning { self.trackingMenus.insert(id) }
                    else { self.trackingMenus.remove(id) }
                    self.controlsState.isMenuTracking = !self.trackingMenus.isEmpty
                    self.controlsState.reveal()
                }
            })
        }
    }

    func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers = []
        trackingMenus = []
        controlsState.isMenuTracking = false
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !isBlocked, !controlsState.isMenuTracking, !controlsState.isPopoverPresented,
              !lifecycle.isPictureInPictureActive, !lifecycle.isFullScreenTransitioning,
              let playerView, let window = event.window,
              window.isKeyWindow, window.attachedSheet == nil, NSApp.modalWindow == nil,
              window === playerView.window else {
            return false
        }

        // Observe Tab even though AppKit/SwiftUI handles the navigation itself.
        controlsState.keyboardActivity(isNavigation: event.keyCode == 48)
        guard let action = Self.action(
            for: event,
            hasFocusedControl: controlsState.hasKeyboardFocus || Self.hasFocusedControl(window.firstResponder),
            isFullScreenActive: lifecycle.isFullScreenActive,
            isScrubbing: controlsState.isScrubbing,
            isTimelineFocused: controlsState.isTimelineFocused,
            isEditingText: window.firstResponder is NSTextView
        ) else { return false }

        // Holding an arrow accumulates seeks. Holding Next or Space must not
        // skip multiple episodes or repeatedly toggle playback.
        controlsState.reveal()
        switch action {
        case .cancelScrub:
            controlsState.scrub.cancel()
        case .togglePlayback:
            if !event.isARepeat { coordinator.togglePlayback() }
        case .skipBackward:
            coordinator.skipBackward()
        case .skipForward:
            coordinator.skipForward()
        case .previous:
            if !event.isARepeat { coordinator.goPrevious() }
        case .next:
            if !event.isARepeat { coordinator.goNext() }
        case .enterFullScreen, .exitFullScreen:
            if allowsFullScreen, !event.isARepeat { toggleFullScreen() }
        }
        return true
    }

    static func hasFocusedControl(_ responder: NSResponder?) -> Bool {
        if responder is NSTextView || responder is NSControl { return true }
        // SwiftUI and AVKit can expose accessible controls without NSControl.
        guard let view = responder as? NSView else { return false }
        return [.textField, .textArea, .slider, .button, .popUpButton, .table, .list]
            .contains(view.accessibilityRole())
    }

    static func action(
        for event: NSEvent,
        hasFocusedControl: Bool,
        isFullScreenActive: Bool = false,
        isScrubbing: Bool = false,
        isTimelineFocused: Bool = false,
        isEditingText: Bool = false
    ) -> Action? {
        let fullScreenModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        // Cancellation belongs to the active gesture, independent of focus.
        if event.keyCode == 53, fullScreenModifiers.isEmpty, isScrubbing, !isEditingText {
            return .cancelScrub
        }
        // The timeline uses the player transport keys, including Space and F.
        // Other controls and text editors retain their normal key handling.
        guard !isEditingText, !hasFocusedControl || isTimelineFocused else { return nil }
        if fullScreenModifiers.isEmpty {
            if event.charactersIgnoringModifiers?.lowercased() == "f" {
                return isFullScreenActive ? .exitFullScreen : .enterFullScreen
            }
            if event.keyCode == 53, isFullScreenActive { return .exitFullScreen }
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        switch (event.keyCode, modifiers) {
        case (123, []): return .skipBackward
        case (124, []): return .skipForward
        case (123, .command): return .previous
        case (124, .command): return .next
        case (49, []) where !event.modifierFlags.contains(.function): return .togglePlayback
        default: return nil
        }
    }
}
