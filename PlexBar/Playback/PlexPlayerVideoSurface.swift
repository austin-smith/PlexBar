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
    }

    static func dismantleNSView(_ view: PlexPlayerVideoNSView, coordinator: ()) {
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
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { controls?.reveal() }
    override func mouseMoved(with event: NSEvent) { controls?.reveal() }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        controls?.reveal()
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
