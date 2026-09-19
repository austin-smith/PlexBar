import AppKit
import AVKit
import Observation

@MainActor
@Observable
final class PlexPlayerPresentationController: NSObject, @MainActor AVPictureInPictureControllerDelegate {
    private(set) var canStartPictureInPicture = false
    var errorMessage: String?
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var lifecycle: PlexPlayerPresentationLifecycle?
    @ObservationIgnored private var pictureInPicture: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    @ObservationIgnored private var windowObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var restoreInterface: ((@escaping (Bool) -> Void) -> Void)?

    func attach(
        layer: AVPlayerLayer,
        lifecycle: PlexPlayerPresentationLifecycle,
        restoreInterface: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        self.lifecycle = lifecycle
        self.restoreInterface = restoreInterface
        guard pictureInPicture == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller = AVPictureInPictureController(playerLayer: layer)
        pictureInPicture = controller
        controller?.delegate = self
        possibleObservation = controller?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor [weak self] in self?.canStartPictureInPicture = possible }
        }
    }

    func attach(window: NSWindow?) {
        guard self.window !== window else { return }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        self.window = window
        guard let window else { return }
        if window.styleMask.contains(.fullScreen) {
            lifecycle?.willEnterFullScreen()
            lifecycle?.didEnterFullScreen()
        } else {
            lifecycle?.didExitFullScreen()
        }
        let notifications: [Notification.Name] = [
            NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification,
        ]
        for name in notifications {
            windowObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] notification in
                let name = notification.name
                MainActor.assumeIsolated { self?.handleWindowNotification(name) }
            })
        }
    }

    private func handleWindowNotification(_ name: Notification.Name) {
        switch name {
        case NSWindow.willEnterFullScreenNotification: lifecycle?.willEnterFullScreen()
        case NSWindow.didEnterFullScreenNotification: lifecycle?.didEnterFullScreen()
        case NSWindow.willExitFullScreenNotification: lifecycle?.willExitFullScreen()
        case NSWindow.didExitFullScreenNotification: lifecycle?.didExitFullScreen()
        default: break
        }
    }

    func toggleFullScreen() {
        guard lifecycle?.isFullScreenTransitioning == false else { return }
        window?.toggleFullScreen(nil)
    }

    func togglePictureInPicture() {
        guard let pictureInPicture else { return }
        if pictureInPicture.isPictureInPictureActive {
            pictureInPicture.stopPictureInPicture()
        } else if pictureInPicture.isPictureInPicturePossible {
            pictureInPicture.startPictureInPicture()
        }
    }

    func stopPictureInPicture() { pictureInPicture?.stopPictureInPicture() }

    func detach() {
        possibleObservation?.invalidate()
        possibleObservation = nil
        pictureInPicture?.stopPictureInPicture()
        pictureInPicture?.delegate = nil
        pictureInPicture = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        window = nil
        restoreInterface = nil
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        lifecycle?.willStartPictureInPicture()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        lifecycle?.didStopPictureInPicture()
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        lifecycle?.failedToStartPictureInPicture()
        errorMessage = error.localizedDescription
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        guard let restoreInterface else { completionHandler(false); return }
        restoreInterface(completionHandler)
    }
}
