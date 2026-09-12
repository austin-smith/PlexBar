import AppKit

final class PlexSystemLifecycleObserver {
    private let notificationCenter: NotificationCenter
    private let didWakeObserver: NSObjectProtocol
    private let willSleepObserver: NSObjectProtocol

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onWillSleep: @escaping @MainActor () -> Void,
        onDidWake: @escaping @MainActor () -> Void
    ) {
        self.notificationCenter = notificationCenter
        willSleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { onWillSleep() }
        }
        didWakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { onDidWake() }
        }
    }

    deinit {
        notificationCenter.removeObserver(didWakeObserver)
        notificationCenter.removeObserver(willSleepObserver)
    }
}
