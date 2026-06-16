import AppKit

final class PlexSystemLifecycleObserver {
    private let notificationCenter: NotificationCenter
    private let didWakeObserver: NSObjectProtocol

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onDidWake: @escaping @MainActor () -> Void
    ) {
        self.notificationCenter = notificationCenter
        didWakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                onDidWake()
            }
        }
    }

    deinit {
        notificationCenter.removeObserver(didWakeObserver)
    }
}
