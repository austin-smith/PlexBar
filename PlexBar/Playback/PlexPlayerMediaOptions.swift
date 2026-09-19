import PlexClientKit
import AVFoundation
import Observation

@MainActor
@Observable
final class PlexPlayerMediaOptions {
    struct Request: Equatable {
        let itemID: ObjectIdentifier?
        let generation: UInt

        init(item: AVPlayerItem?, generation: UInt) {
            itemID = item.map(ObjectIdentifier.init)
            self.generation = generation
        }
    }

    struct Option: Identifiable {
        let value: AVMediaSelectionOption
        var id: ObjectIdentifier { ObjectIdentifier(value) }
        var title: String { value.displayName }
    }

    private(set) var audio: [Option] = []
    private(set) var subtitles: [Option] = []
    private(set) var selectedAudioID: ObjectIdentifier?
    private(set) var selectedSubtitleID: ObjectIdentifier?
    private(set) var allowsSubtitlesOff = false
    var errorMessage: String?
    @ObservationIgnored private weak var item: AVPlayerItem?
    @ObservationIgnored private var audioGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var subtitleGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var request: Request?

    func load(
        item: AVPlayerItem?,
        generation: UInt,
        reportAvailability: (PlexNativeMediaSelectionAvailability, UInt) -> Void
    ) async {
        let request = Request(item: item, generation: generation)
        let previousRequest = self.request
        self.request = request
        self.item = item
        audio = []
        subtitles = []
        audioGroup = nil
        subtitleGroup = nil
        selectedAudioID = nil
        selectedSubtitleID = nil
        allowsSubtitlesOff = false
        errorMessage = nil
        guard let item else { return }
        // Reconfiguration invalidates the old tracks before AVPlayer receives
        // its replacement item. Do not publish the old item's groups as new.
        if previousRequest?.itemID == request.itemID,
           previousRequest?.generation != generation { return }
        do {
            let audioGroup = try await item.asset.loadMediaSelectionGroup(for: .audible)
            let subtitleGroup = try await item.asset.loadMediaSelectionGroup(for: .legible)
            guard !Task.isCancelled, self.request == request else { return }
            self.audioGroup = audioGroup
            self.subtitleGroup = subtitleGroup
            audio = audioGroup?.options.map { Option(value: $0) } ?? []
            subtitles = subtitleGroup?.options.map { Option(value: $0) } ?? []
            allowsSubtitlesOff = subtitleGroup?.allowsEmptySelection == true
            refreshSelection()
            reportAvailability(
                PlexNativeMediaSelectionAvailability(
                    audioOptionCount: audio.count,
                    subtitleOptionCount: subtitles.count
                ),
                generation
            )
            for await _ in NotificationCenter.default.notifications(
                named: AVPlayerItem.mediaSelectionDidChangeNotification,
                object: item
            ).map({ _ in () }) {
                guard !Task.isCancelled, self.request == request else { return }
                refreshSelection()
            }
        } catch {
            guard !Task.isCancelled, self.request == request else { return }
            errorMessage = "Unable to load audio and subtitle tracks: \(error.localizedDescription)"
        }
    }

    func selectAudio(_ option: Option) {
        guard let item, let audioGroup, audio.contains(where: { $0.id == option.id }) else { return }
        item.select(option.value, in: audioGroup)
        refreshSelection()
    }

    func selectSubtitle(_ option: Option?) {
        guard let item, let subtitleGroup,
              option.map({ selected in subtitles.contains(where: { $0.id == selected.id }) })
                ?? allowsSubtitlesOff else { return }
        item.select(option?.value, in: subtitleGroup)
        refreshSelection()
    }

    private func refreshSelection() {
        guard let item else { return }
        selectedAudioID = audioGroup.flatMap {
            item.currentMediaSelection.selectedMediaOption(in: $0).map(ObjectIdentifier.init)
        }
        selectedSubtitleID = subtitleGroup.flatMap {
            item.currentMediaSelection.selectedMediaOption(in: $0).map(ObjectIdentifier.init)
        }
    }
}
