import AppKit
import SwiftUI

struct PlexDownloadsView: View {
    @Bindable var downloadsStore: PlexDownloadsStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    @State private var pendingRemoval: PlexOfflineMedia?
    @State private var pendingRuleRemoval: PlexAutomaticDownloadRule?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let startupErrorMessage = downloadsStore.startupErrorMessage,
               downloadsStore.jobs.isEmpty,
               downloadsStore.downloadedMedia.isEmpty,
               downloadsStore.automaticDownloadRules.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t Load Downloads", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(startupErrorMessage)
                } actions: {
                    Button("Try Again") {
                        Task { await downloadsStore.reload() }
                    }
                }
            } else if downloadsStore.jobs.isEmpty
                && downloadsStore.downloadedMedia.isEmpty
                && downloadsStore.automaticDownloadRules.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle")
            } else {
                List {
                    if !downloadsStore.automaticDownloadRules.isEmpty {
                        Section("Automatic Downloads") {
                            ForEach(downloadsStore.automaticDownloadRules) { rule in
                                PlexAutomaticDownloadRuleRow(
                                    rule: rule,
                                    isRefreshing: downloadsStore.refreshingAutomaticRuleIDs.contains(rule.id),
                                    onRefresh: {
                                        Task {
                                            do {
                                                try await downloadsStore.refreshAutomaticDownload(ruleID: rule.id)
                                            } catch {
                                                errorMessage = error.localizedDescription
                                            }
                                        }
                                    },
                                    onRemove: { pendingRuleRemoval = rule }
                                )
                            }
                        }
                    }

                    if !downloadsStore.activeJobs.isEmpty {
                        Section("Downloading") {
                            ForEach(downloadsStore.activeJobs) { job in
                                PlexDownloadJobRow(
                                    job: job,
                                    progress: downloadsStore.transferProgress[job.id],
                                    onPause: { Task { await downloadsStore.pause(jobID: job.id) } },
                                    onResume: { Task { await downloadsStore.resume(jobID: job.id) } },
                                    onCancel: { Task { await downloadsStore.cancel(jobID: job.id) } }
                                )
                            }
                        }
                    }

                    if !downloadsStore.failedJobs.isEmpty {
                        Section("Failed") {
                            ForEach(downloadsStore.failedJobs) { job in
                                PlexFailedDownloadRow(
                                    job: job,
                                    onRetry: { Task { await downloadsStore.retry(jobID: job.id) } },
                                    onRemove: { Task { await downloadsStore.cancel(jobID: job.id) } }
                                )
                            }
                        }
                    }

                    if !downloadsStore.downloadedMedia.isEmpty {
                        Section("Downloaded") {
                            ForEach(downloadsStore.downloadedMedia) { media in
                                PlexOfflineMediaRow(
                                    media: media,
                                    syncErrorMessage: downloadsStore.syncErrorMessages[media.id],
                                    onPlay: { play(media) },
                                    onRemove: { pendingRemoval = media }
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Downloads")
        .focusedSceneValue(
            \.plexRefreshCommand,
            PlexFocusedCommandAction(
                title: "Refresh Downloads",
                isEnabled: true,
                perform: refresh
            )
        )
        .toolbar {
            ToolbarItem {
                Button("Refresh Downloads", systemImage: "arrow.clockwise", action: refresh)
            }
        }
        .confirmationDialog(
            "Remove Download?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { media in
            Button("Remove Download", role: .destructive) {
                remove(media)
            }
        } message: { media in
            Text("This removes the downloaded copy of \(media.item.title) from this Mac.")
        }
        .confirmationDialog(
            "Remove Automatic Download?",
            isPresented: Binding(
                get: { pendingRuleRemoval != nil },
                set: { if !$0 { pendingRuleRemoval = nil } }
            ),
            presenting: pendingRuleRemoval
        ) { rule in
            Button("Remove Automatic Download", role: .destructive) {
                remove(rule)
            }
        } message: { rule in
            if rule.keepsUpToDate {
                Text("New episodes of \(rule.title) will no longer download. Existing downloads remain on this Mac.")
            } else {
                Text("This removes the saved rule for \(rule.title). Existing downloads remain on this Mac.")
            }
        }
        .alert(
            "Download Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown download error.")
        }
    }

    private func refresh() {
        Task {
            await downloadsStore.reload()
            await downloadsStore.synchronizeOfflineProgress()
        }
    }

    private func play(_ media: PlexOfflineMedia) {
        Task {
            do {
                let presentation = try await downloadsStore.playbackPresentation(for: media)
                playerCoordinator.present(presentation)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ media: PlexOfflineMedia) {
        pendingRemoval = nil
        Task {
            do {
                try await downloadsStore.remove(packageID: media.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ rule: PlexAutomaticDownloadRule) {
        pendingRuleRemoval = nil
        Task {
            do {
                try await downloadsStore.removeAutomaticDownloadRule(rule)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PlexAutomaticDownloadRuleRow: View {
    let rule: PlexAutomaticDownloadRule
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: rule.sourceType == "season" ? "rectangle.stack" : "tv")
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.title)
                    .font(.headline)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let errorMessage = rule.lastErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
            Menu("More", systemImage: "ellipsis.circle") {
                Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                    .disabled(isRefreshing)
                Divider()
                Button("Remove Automatic Download", systemImage: "trash", role: .destructive, action: onRemove)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 5)
    }

    private var detailText: String {
        let updating = rule.keepsUpToDate ? "Downloads new episodes" : "Current episodes only"
        let removal = rule.removesWatchedDownloads ? "Removes watched downloads" : nil
        return [rule.policy.title, updating, removal]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct PlexDownloadJobRow: View {
    let job: PlexDownloadJob
    let progress: PlexDownloadTransferProgress?
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: job.mediaType == "track" ? "music.note" : "film")
                .frame(width: 28)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(job.title)
                    .font(.headline)
                ProgressView(value: fractionCompleted)
                    .accessibilityLabel("Download progress for \(job.title)")
                    .accessibilityValue(progressAccessibilityValue)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if job.state == .paused {
                Button("Resume", systemImage: "play.fill", action: onResume)
                    .labelStyle(.iconOnly)
                    .help("Resume Download")
            } else if job.state == .transferring {
                Button("Pause", systemImage: "pause.fill", action: onPause)
                    .labelStyle(.iconOnly)
                    .help("Pause Download")
            }

            Button("Cancel", systemImage: "xmark", action: onCancel)
                .labelStyle(.iconOnly)
                .help("Cancel Download")
        }
        .padding(.vertical, 5)
    }

    private var fractionCompleted: Double? {
        progress?.fractionCompleted ?? job.serverPreparationProgress
    }

    private var statusText: String {
        switch job.state {
        case .waitingForServer:
            if let errorMessage = job.errorMessage {
                return errorMessage
            }
            if let progress = job.serverPreparationProgress {
                return "Preparing on Plex Server · \(progress.formatted(.percent.precision(.fractionLength(0))))"
            }
            return "Preparing on Plex Server"
        case .transferring:
            if let progress {
                let received = ByteCountFormatter.string(fromByteCount: progress.bytesReceived, countStyle: .file)
                if let expected = progress.bytesExpected {
                    let total = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
                    return "\(received) of \(total)"
                }
                return received
            }
            return "Downloading"
        case .paused:
            return "Paused"
        case .failed:
            return job.errorMessage ?? "Failed"
        }
    }

    private var progressAccessibilityValue: String {
        fractionCompleted?.formatted(.percent.precision(.fractionLength(0))) ?? statusText
    }
}

private struct PlexFailedDownloadRow: View {
    let job: PlexDownloadJob
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(.headline)
                Text(job.errorMessage ?? "Download failed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Retry", systemImage: "arrow.clockwise", action: onRetry)
            Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
                .labelStyle(.iconOnly)
        }
        .padding(.vertical, 5)
    }
}

private struct PlexOfflineMediaRow: View {
    let media: PlexOfflineMedia
    let syncErrorMessage: String?
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PlexDownloadedArtwork(
                url: media.package.artworkURL,
                placeholderSystemImage: media.item.type == "track" ? "music.note" : "film"
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(media.item.title)
                    .font(.headline)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let syncErrorMessage {
                    Text(syncErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("Play", systemImage: "play.fill", action: onPlay)
                .buttonStyle(.borderedProminent)
            Menu("More", systemImage: "ellipsis.circle") {
                Button("Remove Download", systemImage: "trash", role: .destructive, action: onRemove)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 5)
    }

    private var detailText: String {
        let size = ByteCountFormatter.string(
            fromByteCount: media.package.manifest.mediaByteCount,
            countStyle: .file
        )
        let date = media.package.manifest.completedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(size) · \(date)"
    }
}

private struct PlexDownloadedArtwork: View {
    let url: URL?
    let placeholderSystemImage: String

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSystemImage)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(.secondary)
                    .background(.quaternary)
            }
        }
        .frame(width: 44, height: 64)
        .compositingGroup()
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}
