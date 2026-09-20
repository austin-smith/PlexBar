import PlexClientKit
import PlexModels
import SwiftUI

/// Keeps the macOS detail order: credits, details, extras, then Plex's related hubs.
struct TVDetailDiscoveryView: View {
    @Environment(TVAppStore.self) private var store
    let item: PlexMediaItem

    @State private var extras: [PlexMediaItem] = []
    @State private var relatedHubs: [PlexHub] = []
    @State private var extrasLoading = true
    @State private var relatedLoading = true
    @State private var extrasError: String?
    @State private var relatedError: String?
    @State private var extrasReloadID = UUID()
    @State private var relatedReloadID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
            if item.supportsMediaExtras, extrasLoading, extras.isEmpty {
                ProgressView("Loading Extras")
                    .safeAreaPadding(.horizontal)
            }
            if let extrasError {
                loadError(title: "Couldn’t Load Extras", message: extrasError) {
                    extrasReloadID = UUID()
                }
            }
            if !extras.isEmpty {
                TVMediaShelf(title: "Extras", items: extras)
            }

            if relatedLoading, relatedHubs.isEmpty {
                ProgressView("Loading Related Content")
                    .safeAreaPadding(.horizontal)
            }
            if let relatedError {
                loadError(title: "Couldn’t Load Related Content", message: relatedError) {
                    relatedReloadID = UUID()
                }
            }
            ForEach(relatedHubs) { hub in
                TVMediaShelf(hub: hub)
            }
        }
        .task(id: loadIdentity(reloadID: extrasReloadID)) {
            extrasLoading = true
            extrasError = nil
            do {
                let result = try await store.mediaExtras(for: item)
                guard !Task.isCancelled else { return }
                extras = result
            } catch {
                guard !Task.isCancelled else { return }
                extrasError = error.localizedDescription
            }
            extrasLoading = false
        }
        .task(id: loadIdentity(reloadID: relatedReloadID)) {
            relatedLoading = true
            relatedError = nil
            do {
                let result = try await store.relatedHubs(for: item)
                guard !Task.isCancelled else { return }
                relatedHubs = result
            } catch {
                guard !Task.isCancelled else { return }
                relatedError = error.localizedDescription
            }
            relatedLoading = false
        }
    }

    private func loadIdentity(reloadID: UUID) -> LoadIdentity {
        LoadIdentity(ratingKey: item.ratingKey, connection: store.connection,
                     revision: store.playbackMetadataRevision, reloadID: reloadID)
    }

    private func loadError(title: String, message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(TVTypography.sectionTitle)
            Text(message).font(TVTypography.metadata).foregroundStyle(.secondary)
            Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                .font(TVTypography.action)
        }
        .safeAreaPadding(.horizontal)
    }

    private struct LoadIdentity: Equatable {
        let ratingKey: String
        let connection: TVPlexConnection?
        let revision: UUID
        let reloadID: UUID
    }
}
