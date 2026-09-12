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

struct PlexMediaSelectionRequestParameters: Equatable, Sendable {
    let partID: Int
    let audioStreamID: Int?
    let subtitleStreamID: Int?
    let allParts: Bool

    var hasSelection: Bool {
        audioStreamID != nil || subtitleStreamID != nil
    }

    var path: String {
        "/library/parts/\(partID)"
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let audioStreamID {
            items.append(URLQueryItem(name: "audioStreamID", value: String(audioStreamID)))
        }
        if let subtitleStreamID {
            items.append(URLQueryItem(name: "subtitleStreamID", value: String(subtitleStreamID)))
        }
        items.append(URLQueryItem(name: "allParts", value: allParts ? "1" : "0"))
        return items
    }
}

struct PlexSubtitleOffsetRequestParameters: Equatable, Sendable {
    let streamID: Int
    let milliseconds: Int

    var path: String {
        "/library/streams/\(streamID)"
    }

    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "offset", value: String(milliseconds))]
    }
}

struct PlexSubtitleOffsetSelection: Equatable, Sendable {
    static let adjustmentStepMilliseconds = 100

    let streamID: Int
    let milliseconds: Int

    var displayValue: String {
        guard milliseconds != 0 else { return "0 ms" }
        let sign = milliseconds > 0 ? "+" : "−"
        return "\(sign)\(milliseconds.magnitude) ms"
    }

    func adjusted(by delta: Int) -> Int? {
        let result = milliseconds.addingReportingOverflow(delta)
        return result.overflow ? nil : result.partialValue
    }
}

struct PlexNativeMediaSelectionAvailability: Equatable, Sendable {
    let audioOptionCount: Int
    let subtitleOptionCount: Int
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
    let subtitleOffsetSelection: PlexSubtitleOffsetSelection?

    init(item: PlexMediaItem, source: PlexPlaybackSource) {
        guard item.media.indices.contains(source.mediaIndex) else {
            partID = nil
            audioOptions = []
            subtitleOptions = []
            subtitleOffsetSelection = nil
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
        subtitleOffsetSelection = Self.subtitleOffsetSelection(from: part?.streams ?? [])
    }

    var hasActionMenuItems: Bool {
        audioOptions.count > 1 || !subtitleOptions.isEmpty
    }

    var hasSelectedSubtitle: Bool {
        subtitleOptions.contains(where: \.isSelected)
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

    private static func subtitleOffsetSelection(
        from streams: [PlexMediaStream]
    ) -> PlexSubtitleOffsetSelection? {
        let textSubtitleCodecs = Set(["ass", "srt", "ssa", "subrip", "vtt", "webvtt"])
        guard let stream = streams.first(where: { stream in
            stream.streamType == 3
                && stream.selected == true
                && stream.location?.lowercased() == "external"
                && stream.codec.map { textSubtitleCodecs.contains($0.lowercased()) } == true
        }), let streamID = stream.id else {
            return nil
        }
        return PlexSubtitleOffsetSelection(
            streamID: streamID,
            milliseconds: stream.offset ?? 0
        )
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

        audioOptions = nativeAvailability.audioOptionCount >= selection.audioOptions.count
            || selection.audioOptions.count < 2
            ? []
            : selection.audioOptions
        subtitleOptions = nativeAvailability.subtitleOptionCount >= selection.subtitleOptions.count
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
