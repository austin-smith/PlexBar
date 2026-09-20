import PlexModels
import Foundation

public struct PlexMediaSelectionOption: Equatable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let languageTag: String?
    public let isSelected: Bool
    public let isForced: Bool
    public let isHearingImpaired: Bool
    public let isVisualImpaired: Bool

    public init(
        id: Int,
        title: String,
        languageTag: String? = nil,
        isSelected: Bool,
        isForced: Bool,
        isHearingImpaired: Bool,
        isVisualImpaired: Bool
    ) {
        self.id = id
        self.title = title
        self.languageTag = languageTag
        self.isSelected = isSelected
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
        self.isVisualImpaired = isVisualImpaired
    }
}

public struct PlexMediaSelectionRequestParameters: Equatable, Sendable {
    public let partID: Int
    public let audioStreamID: Int?
    public let subtitleStreamID: Int?
    public let allParts: Bool

    public var hasSelection: Bool {
        audioStreamID != nil || subtitleStreamID != nil
    }

    public var path: String {
        "/library/parts/\(partID)"
    }

    public var queryItems: [URLQueryItem] {
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

    public init(partID: Int, audioStreamID: Int? = nil, subtitleStreamID: Int? = nil, allParts: Bool) {
        self.partID = partID
        self.audioStreamID = audioStreamID
        self.subtitleStreamID = subtitleStreamID
        self.allParts = allParts
    }
}

public struct PlexSubtitleOffsetRequestParameters: Equatable, Sendable {
    public let streamID: Int
    public let milliseconds: Int

    public var path: String {
        "/library/streams/\(streamID)"
    }

    public var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "offset", value: String(milliseconds))]
    }

    public init(streamID: Int, milliseconds: Int) {
        self.streamID = streamID
        self.milliseconds = milliseconds
    }
}

public struct PlexSubtitleOffsetSelection: Equatable, Sendable {
    public static let adjustmentStepMilliseconds = 100

    public let streamID: Int
    public let milliseconds: Int

    public var displayValue: String {
        guard milliseconds != 0 else { return "0 ms" }
        let sign = milliseconds > 0 ? "+" : "−"
        return "\(sign)\(milliseconds.magnitude) ms"
    }

    public func adjusted(by delta: Int) -> Int? {
        let result = milliseconds.addingReportingOverflow(delta)
        return result.overflow ? nil : result.partialValue
    }

    public init(streamID: Int, milliseconds: Int) {
        self.streamID = streamID
        self.milliseconds = milliseconds
    }
}

public struct PlexNativeMediaSelectionAvailability: Equatable, Sendable {
    public let audioOptionCount: Int
    public let subtitleOptionCount: Int

    public init(audioOptionCount: Int, subtitleOptionCount: Int) {
        self.audioOptionCount = audioOptionCount
        self.subtitleOptionCount = subtitleOptionCount
    }
}

public struct PlexNativeMediaSelectionState: Equatable, Sendable {
    public private(set) var generation: UInt = 0
    public private(set) var availability: PlexNativeMediaSelectionAvailability?

    public mutating func beginReload() {
        generation &+= 1
        availability = nil
    }

    public mutating func accept(
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

    public init(generation: UInt = 0, availability: PlexNativeMediaSelectionAvailability? = nil) {
        self.generation = generation
        self.availability = availability
    }
}

public struct PlexPlaybackMediaSelection: Equatable, Sendable {
    public let partID: Int?
    public let audioOptions: [PlexMediaSelectionOption]
    public let subtitleOptions: [PlexMediaSelectionOption]
    public let subtitleOffsetSelection: PlexSubtitleOffsetSelection?

    public init(item: PlexMediaItem, source: PlexPlaybackSource) {
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

    public var hasActionMenuItems: Bool {
        audioOptions.count > 1 || !subtitleOptions.isEmpty
    }

    public var hasSelectedSubtitle: Bool {
        subtitleOptions.contains(where: \.isSelected)
    }

    public func canSelectAudioStream(_ streamID: Int) -> Bool {
        audioOptions.contains { option in
            option.id == streamID && !option.isSelected
        }
    }

    public func canSelectSubtitleStream(_ streamID: Int?) -> Bool {
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

public struct PlexServerManagedMediaSelection: Equatable, Sendable {
    public let audioOptions: [PlexMediaSelectionOption]
    public let subtitleOptions: [PlexMediaSelectionOption]

    public init(
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

    public init() {
        audioOptions = []
        subtitleOptions = []
    }

    public var hasChoices: Bool {
        !audioOptions.isEmpty || !subtitleOptions.isEmpty
    }

    public func canSelectAudioStream(_ streamID: Int) -> Bool {
        audioOptions.contains { option in
            option.id == streamID && !option.isSelected
        }
    }

    public func canSelectSubtitleStream(_ streamID: Int?) -> Bool {
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
