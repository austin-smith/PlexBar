import SwiftUI

struct StudioAcceptArtworkButton: View {
    let store: StudioStore
    let candidate: StudioCandidate
    var onAccepted: () -> Void = {}
    var onFailure: () -> Void = {}
    @State private var replacement: StudioJob.Destination?

    var body: some View {
        Button("Accept & Save") {
            if store.needsReplacementConfirmation(candidate) {
                do { replacement = try store.destinationSnapshot(path: candidate.assetPath) }
                catch { store.errorMessage = error.localizedDescription; onFailure() }
            } else { accept() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isBusy)
        .confirmationDialog("Replace the current \(candidate.role.title.lowercased())?", isPresented: Binding(
            get: { replacement != nil }, set: { if !$0 { replacement = nil } }
        ), titleVisibility: .visible) {
            Button("Replace Artwork", role: .destructive) { accept(replacing: replacement) }
            Button("Cancel", role: .cancel) { replacement = nil }
        } message: {
            Text("The accepted artwork for \(candidate.title) changed after this generation started. This will replace it with this draft.")
        }
    }

    private func accept(replacing destination: StudioJob.Destination? = nil) {
        if store.decide(candidate, accept: true, replacing: destination) { onAccepted() }
        else { onFailure() }
    }
}
