import AppKit
import SwiftUI

/// The palette is SwiftUI; AppKit owns window modality and first-responder restoration.
@MainActor
final class PlexCommandPaletteWindowContext {
    private weak var window: NSWindow?
    private weak var store: PlexCommandPaletteStore?
    private weak var previousResponder: NSResponder?
    private var previousSelection: NSRange?
    private var observers: [NSObjectProtocol] = []
    private var dismissalAction: (() -> Void)?
    private var restoresFocus = true
    private var generation = 0

    var isComposingText: Bool {
        (window?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    func attach(to window: NSWindow?, store: PlexCommandPaletteStore) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        self.store = store
        guard let window else { return }
        store.requestPresentation = { [weak self] in self?.presentIfRequested() }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willCloseNotification, NSWindow.willBeginSheetNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] notification in
                let becameKey = notification.name == NSWindow.didBecomeKeyNotification
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if becameKey {
                        self.presentIfRequested()
                    } else {
                        self.dismissalAction = nil
                        self.store?.dismiss()
                    }
                }
            })
        }
        // A newly created window finishes attaching before it can receive focus.
        Task { @MainActor [weak self] in self?.presentIfRequested() }
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        store?.requestPresentation = nil
        window = nil
        previousResponder = nil
        dismissalAction = nil
    }

    func dismiss(restoringFocus: Bool = true, perform action: (() -> Void)? = nil) {
        restoresFocus = restoringFocus
        dismissalAction = action
        store?.dismiss()
    }

    func presentationDidDisappear() {
        let generation = generation
        // Restore only after SwiftUI removes the palette and re-enables the content.
        Task { @MainActor [weak self] in
            guard let self, self.generation == generation, self.store?.isPresented == false else { return }
            let action = self.dismissalAction
            self.dismissalAction = nil
            defer {
                self.previousResponder = nil
                self.previousSelection = nil
            }
            guard let window = self.window, window.isKeyWindow,
                  window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
            if self.restoresFocus, let responder = self.previousResponder,
               (responder as? NSView).map({ $0.window === window }) ?? true {
                if window.makeFirstResponder(responder), let range = self.previousSelection,
                   let editor = window.firstResponder as? NSTextView,
                   range.location + range.length <= editor.string.utf16.count {
                    editor.setSelectedRange(range)
                }
            }
            action?()
        }
    }

    private func presentIfRequested() {
        guard let store, store.isPresentationRequested, !store.isPresented,
              let window else { return }
        guard window.attachedSheet == nil, NSApp.modalWindow == nil else {
            store.dismiss()
            return
        }
        guard window.isKeyWindow else { return }
        generation += 1
        dismissalAction = nil
        restoresFocus = true
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor {
            previousResponder = editor.delegate as? NSResponder
            previousSelection = editor.selectedRange()
        } else {
            previousResponder = window.firstResponder
            previousSelection = nil
        }
        // End editing before presenting so keystrokes cannot reach the old field
        // while SwiftUI attaches the palette's search field.
        window.makeFirstResponder(nil)
        store.present()
    }
}

struct PlexCommandPaletteWindowReader: NSViewRepresentable {
    let context: PlexCommandPaletteWindowContext
    let store: PlexCommandPaletteStore

    func makeNSView(context: Context) -> WindowReader {
        WindowReader(paletteContext: self.context, store: store)
    }

    func updateNSView(_ nsView: WindowReader, context: Context) { }

    static func dismantleNSView(_ nsView: WindowReader, coordinator: ()) {
        nsView.paletteContext.detach()
    }

    final class WindowReader: NSView {
        let paletteContext: PlexCommandPaletteWindowContext
        let store: PlexCommandPaletteStore

        init(paletteContext: PlexCommandPaletteWindowContext, store: PlexCommandPaletteStore) {
            self.paletteContext = paletteContext
            self.store = store
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            paletteContext.attach(to: window, store: store)
        }
    }
}
