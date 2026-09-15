import AppKit
import SwiftUI

struct PlexActivityVisibility: ViewModifier {
    let store: PlexSessionStore
    var isEnabled = true
    @State private var consumer = UUID()
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .background {
                ActivityWindowVisibility(isEnabled: isEnabled && isPresented) { visible in
                    store.setActivityVisible(visible, consumer: consumer)
                }
                .frame(width: 0, height: 0)
            }
            .onAppear { isPresented = true }
            .onDisappear {
                isPresented = false
                store.setActivityVisible(false, consumer: consumer)
            }
    }
}

private struct ActivityWindowVisibility: NSViewRepresentable {
    let isEnabled: Bool
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> PlexActivityVisibilityView {
        PlexActivityVisibilityView()
    }

    func updateNSView(_ view: PlexActivityVisibilityView, context: Context) {
        view.isEnabled = isEnabled
        view.onChange = onChange
        view.scheduleVisibilityUpdate()
    }

    static func dismantleNSView(_ view: PlexActivityVisibilityView, coordinator: ()) {
        view.stopObserving()
    }
}

// SwiftUI appearance alone doesn't describe a closed menu panel, a minimized
// window, or a window covered by another app. Observe the actual hosting window.
final class PlexActivityVisibilityView: NSView {
    var isEnabled = false
    var onChange: (@MainActor (Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var updateTask: Task<Void, Never>?
    private var lastVisibility = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification,
                     NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleVisibilityUpdate() }
            })
        }
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleVisibilityUpdate() }
            })
        }
        scheduleVisibilityUpdate()
    }

    override func viewDidHide() {
        super.viewDidHide()
        scheduleVisibilityUpdate()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        scheduleVisibilityUpdate()
    }

    func scheduleVisibilityUpdate() {
        updateTask?.cancel()
        // Deliver after the representable update, never mutate observed SwiftUI
        // state from inside updateNSView. Read current visibility at delivery time.
        updateTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            let visible = self.isEnabled && !self.isHiddenOrHasHiddenAncestor
                && self.window?.isVisible == true
                && self.window?.isMiniaturized == false
                && self.window?.occlusionState.contains(.visible) == true
            self.publish(visible)
        }
    }

    func stopObserving() {
        updateTask?.cancel()
        updateTask = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        publish(false)
    }

    private func publish(_ visible: Bool) {
        guard visible != lastVisibility else { return }
        lastVisibility = visible
        onChange?(visible)
    }
}
