import AppKit

@MainActor
final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    var store: StudioStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.hasActiveGenerations else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop generations and quit?"
        alert.informativeText = "Running and queued generations will stop. Saved drafts will remain available."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        Task {
            await store.shutdownGenerations()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
