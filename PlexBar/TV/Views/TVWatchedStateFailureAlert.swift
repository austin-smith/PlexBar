import SwiftUI

struct TVWatchedStateFailureAlert: ViewModifier {
    @Environment(TVAppStore.self) private var store
    let isActive: Bool

    func body(content: Content) -> some View {
        // Capture the presented failure so dismissal cannot remove a later failure.
        let failure = store.watchedStateFailures.first
        content.alert("Couldn’t Update Watched Status", isPresented: Binding(
            get: { isActive && failure != nil },
            set: { shown in
                if !shown, isActive, let failure {
                    store.dismissWatchedStateFailure(failure)
                }
            }
        ), presenting: failure) { failure in
            Button("Try Again") { store.retryWatchedStateUpdate(failure) }
            Button("Dismiss", role: .cancel) { store.dismissWatchedStateFailure(failure) }
        } message: { failure in
            Text("Plex couldn’t mark “\(failure.update.item.title)” as watched. \(failure.message)")
        }
    }
}
