import AppKit
import Foundation
import Testing
@testable import PlexBar

@MainActor
@Test func systemWakeNotificationRunsWakeHandler() async throws {
    let notificationCenter = NotificationCenter()
    let counter = LifecycleObserverCounter()
    do {
        let observer = PlexSystemLifecycleObserver(
            notificationCenter: notificationCenter
        ) {
            counter.increment()
        }

        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        await waitForLifecycleObserver {
            counter.value == 1
        }

        #expect(counter.value == 1)
        withExtendedLifetime(observer) {}
    }

    notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(50))

    #expect(counter.value == 1)
}

@MainActor
private func waitForLifecycleObserver(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() {
            return
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
private final class LifecycleObserverCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
