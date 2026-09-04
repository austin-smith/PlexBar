import Foundation

struct PlexMediaSelectionOption: Equatable, Identifiable, Sendable {
    let id: Int
    let title: String
    let languageTag: String?
    let isSelected: Bool
    let isForced: Bool
    let isHearingImpaired: Bool
    let isVisualImpaired: Bool
}

struct PlexNativeMediaSelectionAvailability: Equatable, Sendable {
    let hasAudio: Bool
    let hasSubtitles: Bool
}

struct PlexNativeMediaSelectionState: Equatable, Sendable {
    private(set) var generation: UInt = 0
    private(set) var availability: PlexNativeMediaSelectionAvailability?

    mutating func beginReload() {
        generation &+= 1
        availability = nil
    }

    mutating func accept(
        _ availability: PlexNativeMediaSelectionAvailability,
        generation: UInt
    ) -> Bool {
        guard generation == self.generation,
              availability != self.availability else {
            return false
        }
        self.availability = availability
        return true
    }
}

struct PlexPlaybackMediaSelection: Equatable, Sendable {
    let partID: Int?
    let audioOptions: [PlexMediaSelectionOption]
    let subtitleOptions: [PlexMediaSelectionOption]

    init(item: PlexMediaItem, source: PlexPlaybackSource) {
        guard item.media.indices.contains(source.mediaIndex) else {
            partID = nil
            audioOptions = []
            subtitleOptions = []
            return
        }

        let parts = item.media[source.mediaIndex].parts
        let part: PlexMediaPart? = if parts.indices.contains(source.partIndex) {
            parts[source.partIndex]
        } else if source.partIndex == -1 {
            parts.first(where: { $0.selected == true }) ?? parts.first
        } else {
            nil
        }

        partID = part?.id
        audioOptions = Self.options(from: part?.streams ?? [], streamType: 2)
        subtitleOptions = Self.options(from: part?.streams ?? [], streamType: 3)
    }

    var hasActionMenuItems: Bool {
        audioOptions.count > 1 || !subtitleOptions.isEmpty
    }

    func canSelectAudioStream(_ streamID: Int) -> Bool {
        audioOptions.contains { option in
            option.id == streamID && !option.isSelected
        }
    }

    func canSelectSubtitleStream(_ streamID: Int?) -> Bool {
        let selectedStreamID = subtitleOptions.first(where: \.isSelected)?.id
        guard selectedStreamID != streamID else {
            return false
        }
        guard let streamID else {
            return selectedStreamID != nil
        }
        return subtitleOptions.contains { $0.id == streamID }
    }

    private static func options(
        from streams: [PlexMediaStream],
        streamType: Int
    ) -> [PlexMediaSelectionOption] {
        streams.compactMap { stream in
            guard stream.streamType == streamType, let id = stream.id else {
                return nil
            }
            return PlexMediaSelectionOption(
                id: id,
                title: stream.selectionTitle,
                languageTag: stream.nowPlayingLanguageTag,
                isSelected: stream.selected == true,
                isForced: stream.forced == true,
                isHearingImpaired: stream.hearingImpaired == true,
                isVisualImpaired: stream.visualImpaired == true
            )
        }
    }
}

struct PlexServerManagedMediaSelection: Equatable, Sendable {
    let audioOptions: [PlexMediaSelectionOption]
    let subtitleOptions: [PlexMediaSelectionOption]

    init(
        selection: PlexPlaybackMediaSelection,
        nativeAvailability: PlexNativeMediaSelectionAvailability?
    ) {
        guard let nativeAvailability else {
            audioOptions = []
            subtitleOptions = []
            return
        }

        audioOptions = nativeAvailability.hasAudio || selection.audioOptions.count < 2
            ? []
            : selection.audioOptions
        subtitleOptions = nativeAvailability.hasSubtitles
            ? []
            : selection.subtitleOptions
    }

    init() {
        audioOptions = []
        subtitleOptions = []
    }

    var hasChoices: Bool {
        !audioOptions.isEmpty || !subtitleOptions.isEmpty
    }

    func canSelectAudioStream(_ streamID: Int) -> Bool {
        audioOptions.contains { option in
            option.id == streamID && !option.isSelected
        }
    }

    func canSelectSubtitleStream(_ streamID: Int?) -> Bool {
        let selectedStreamID = subtitleOptions.first(where: \.isSelected)?.id
        guard selectedStreamID != streamID else {
            return false
        }
        guard let streamID else {
            return selectedStreamID != nil
        }
        return subtitleOptions.contains { $0.id == streamID }
    }
}

private extension PlexMediaStream {
    var nowPlayingLanguageTag: String? {
        guard let languageCode = languageCode?.nilIfBlank,
              languageCode.range(
                  of: #"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$"#,
                  options: .regularExpression
              ) != nil else {
            return nil
        }
        return languageCode
    }

    var selectionTitle: String {
        var facts: [String] = []
        if let displayTitle = displayTitle?.nilIfBlank {
            facts.append(displayTitle)
        } else if let title = title?.nilIfBlank {
            facts.append(title)
        } else if let language = language?.nilIfBlank {
            facts.append(language)
        } else if let languageCode = languageCode?.nilIfBlank {
            facts.append(languageCode.uppercased())
        } else {
            facts.append("Unknown")
        }

        if let codec = codec?.nilIfBlank,
           !facts.contains(where: { $0.localizedCaseInsensitiveContains(codec) }) {
            facts.append(codec.uppercased())
        }
        if let channels, channels > 0 {
            facts.append("\(channels) ch")
        }
        if forced == true {
            facts.append("Forced")
        }
        if hearingImpaired == true {
            facts.append("SDH")
        }
        if visualImpaired == true {
            facts.append("Audio Description")
        }
        return facts.joined(separator: " · ")
    }
}
