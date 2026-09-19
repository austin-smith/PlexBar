import PlexClientKit
import AVKit
import SwiftUI

struct PlexPlayerVideoSurface: NSViewRepresentable {
    let player: AVPlayer
    let presentation: PlexPlayerPresentationController
    let controls: PlexPlayerControlsState
    let coordinator: PlexPlayerCoordinator
    let lifecycle: PlexPlayerPresentationLifecycle
    let videoDynamicRange: PlexVideoDisplayDynamicRange
    let videoScalingMode: PlexVideoScalingMode
    let isVideo: Bool
    let isInteractionBlocked: Bool
    let isCursorHidingAllowed: Bool
    let restorePlayerInterface: (@escaping (Bool) -> Void) -> Void

    func makeNSView(context: Context) -> PlexPlayerVideoNSView {
        let view = PlexPlayerVideoNSView()
        view.playerLayer.player = player
        view.controls = controls
        view.presentation = presentation
        presentation.attach(
            layer: view.playerLayer,
            lifecycle: lifecycle,
            restoreInterface: restorePlayerInterface
        )
        let keyboard = PlexPlayerTransportKeyboardHandler(
            playerView: view,
            lifecycle: lifecycle,
            coordinator: coordinator,
            controlsState: controls,
            toggleFullScreen: presentation.toggleFullScreen
        )
        view.keyboard = keyboard
        keyboard.start()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PlexPlayerVideoNSView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        view.playerLayer.videoGravity = videoScalingMode.avVideoGravity
        view.playerLayer.preferredDynamicRange = videoDynamicRange.layerDynamicRange
        view.keyboard?.isBlocked = isInteractionBlocked
        view.keyboard?.allowsFullScreen = isVideo
        view.isCursorHidingAllowed = isCursorHidingAllowed
    }

    static func dismantleNSView(_ view: PlexPlayerVideoNSView, coordinator: ()) {
        view.stopPointerMonitoring()
        view.keyboard?.stop()
        view.controls?.stop()
        view.presentation?.detach()
        view.playerLayer.player = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PlexPlayerVideoNSView, context: Context) -> CGSize? {
        PlexNativePlayerSizing.exactSize(for: proposal)
    }
}

@MainActor
final class PlexPlayerVideoNSView: NSView {
    let playerLayer = AVPlayerLayer()
    weak var controls: PlexPlayerControlsState?
    weak var presentation: PlexPlayerPresentationController?
    var keyboard: PlexPlayerTransportKeyboardHandler?
    private var pointerTrackingArea: NSTrackingArea?
    private var pointerMonitor: Any?
    private weak var monitoredWindow: NSWindow?
    private var previouslyAcceptedMouseMovedEvents = false
    private var activationObservers: [NSObjectProtocol] = []
    private(set) var isCursorHidden = false
    var setCursorHiddenUntilMouseMoves: (Bool) -> Void = NSCursor.setHiddenUntilMouseMoves
    var isCursorHidingAllowed = false {
        didSet { updateCursorVisibility() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = playerLayer
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        presentation?.attach(window: window)
        startPointerMonitoring()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        stopPointerMonitoring()
        super.viewWillMove(toWindow: newWindow)
    }

    private func startPointerMonitoring() {
        guard let window else { return }
        monitoredWindow = window
        previouslyAcceptedMouseMovedEvents = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        // Observe the player rectangle, including SwiftUI controls layered above
        // this view. A fading overlay must not create a dead area for mouse input.
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointerEvent(event) }
            return event
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification,
                     NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
                     NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification] {
            activationObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.setCursorHidden(false)
                    self?.controls?.reveal()
                }
            })
        }
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification] {
            activationObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.setCursorHidden(false)
                    self?.controls?.reveal()
                }
            })
        }
    }

    func stopPointerMonitoring() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
        monitoredWindow?.acceptsMouseMovedEvents = previouslyAcceptedMouseMovedEvents
        monitoredWindow = nil
        activationObservers.forEach(NotificationCenter.default.removeObserver)
        activationObservers = []
        setCursorHidden(false)
    }

    func handlePointerEvent(_ event: NSEvent) {
        setCursorHidden(false)
        guard let window, event.window === window, window.isKeyWindow,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              !isHiddenOrHasHiddenAncestor else { return }
        controls?.pointerActivity()
    }

    func updateCursorVisibility(applicationIsActive: Bool = NSApp.isActive) {
        guard isCursorHidingAllowed, let window, window.isKeyWindow,
              applicationIsActive, window.isVisible, !window.isMiniaturized,
              window.attachedSheet == nil, !isHiddenOrHasHiddenAncestor,
              bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) else {
            setCursorHidden(false)
            return
        }
        setCursorHidden(true)
    }

    private func setCursorHidden(_ hidden: Bool) {
        guard isCursorHidden != hidden else { return }
        isCursorHidden = hidden
        // This API must be undone with false, not NSCursor.unhide().
        setCursorHiddenUntilMouseMoves(hidden)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseExited(with event: NSEvent) { setCursorHidden(false) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        controls?.pointerActivity()
        if event.clickCount == 2, keyboard?.allowsFullScreen == true {
            presentation?.toggleFullScreen()
        }
    }
}

extension PlexVideoDisplayDynamicRange {
    var layerDynamicRange: CALayer.DynamicRange {
        switch self {
        case .automatic: .automatic
        case .standard: .standard
        case .constrainedHigh: .constrainedHigh
        case .high: .high
        }
    }
}
