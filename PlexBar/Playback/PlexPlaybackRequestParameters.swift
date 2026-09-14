import PlexModels
import Foundation

enum PlexSubtitleBurnMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case always
    case imageFormatsOnly

    var id: Self { self }

    var label: String {
        switch self {
        case .automatic:
            "Automatic"
        case .always:
            "Always"
        case .imageFormatsOnly:
            "Only Image Formats"
        }
    }

    var explanation: String {
        switch self {
        case .automatic:
            "Burn image-based and complex styled subtitles when needed."
        case .always:
            "Burn the selected subtitle into the video."
        case .imageFormatsOnly:
            "Burn image-based subtitles and convert advanced text subtitles when needed."
        }
    }

    fileprivate var requestValues: (subtitles: String, advancedSubtitles: String) {
        switch self {
        case .automatic:
            (subtitles: "auto", advancedSubtitles: "burn")
        case .always:
            (subtitles: "burn", advancedSubtitles: "burn")
        case .imageFormatsOnly:
            (subtitles: "auto", advancedSubtitles: "text")
        }
    }
}

enum PlexSubtitleSize: Int, CaseIterable, Identifiable, Sendable {
    case tiny = 60
    case small = 80
    case normal = 100
    case large = 120
    case huge = 150

    var id: Self { self }

    var label: String {
        switch self {
        case .tiny: "Tiny"
        case .small: "Small"
        case .normal: "Normal"
        case .large: "Large"
        case .huge: "Huge"
        }
    }

    var percentageLabel: String {
        "\(rawValue)%"
    }
}

struct PlexPlaybackRequestParameters {
    let item: PlexMediaItem
    let source: PlexPlaybackSource
    let videoQuality: PlexVideoQuality
    let musicQuality: PlexMusicQuality
    let audioBoost: PlexAudioBoost
    let streamingPolicy: PlexPlaybackStreamingPolicy
    let subtitleBurnMode: PlexSubtitleBurnMode
    let subtitleSize: PlexSubtitleSize
    let automaticallySyncSubtitles: Bool
    let automaticallyAdjustVideoQuality: Bool
    let playSmallerVideosAtOriginalQuality: Bool
    let forceVideoTranscode: Bool
    let sessionIdentifier: String
    let startTime: TimeInterval
    let forceServerMediaSelection: Bool

    init(
        item: PlexMediaItem,
        source: PlexPlaybackSource,
        videoQuality: PlexVideoQuality,
        musicQuality: PlexMusicQuality = .original,
        audioBoost: PlexAudioBoost = .none,
        streamingPolicy: PlexPlaybackStreamingPolicy,
        subtitleBurnMode: PlexSubtitleBurnMode = .automatic,
        subtitleSize: PlexSubtitleSize = .normal,
        automaticallySyncSubtitles: Bool = true,
        automaticallyAdjustVideoQuality: Bool = false,
        playSmallerVideosAtOriginalQuality: Bool = true,
        forceVideoTranscode: Bool = false,
        sessionIdentifier: String,
        startTime: TimeInterval,
        forceServerMediaSelection: Bool
    ) {
        self.item = item
        self.source = source
        self.videoQuality = videoQuality
        self.musicQuality = musicQuality
        self.audioBoost = audioBoost
        self.streamingPolicy = streamingPolicy
        self.subtitleBurnMode = subtitleBurnMode
        self.subtitleSize = subtitleSize
        self.automaticallySyncSubtitles = automaticallySyncSubtitles
        self.automaticallyAdjustVideoQuality = automaticallyAdjustVideoQuality
        self.playSmallerVideosAtOriginalQuality = playSmallerVideosAtOriginalQuality
        self.forceVideoTranscode = forceVideoTranscode
        self.sessionIdentifier = sessionIdentifier
        self.startTime = startTime
        self.forceServerMediaSelection = forceServerMediaSelection
    }

    var permitsDirectPlay: Bool {
        streamingPolicy.allowsDirectPlay
            && !videoQuality.limits(media: item.media[source.mediaIndex])
            && !musicQuality.limits(media: item.media[source.mediaIndex])
            && permitsOriginalVideoQuality
            && !forcesVideoTranscode
            && !forceServerMediaSelection
            && !(automaticallySyncSubtitles && supportsSubtitleAutoSync)
    }

    var hasMultichannelAudioSource: Bool {
        let media = item.media[source.mediaIndex]
        let parts: ArraySlice<PlexMediaPart>
        if source.partIndex >= 0, media.parts.indices.contains(source.partIndex) {
            parts = media.parts[source.partIndex...source.partIndex]
        } else {
            parts = media.parts[...]
        }
        guard !parts.isEmpty else { return false }

        return parts.allSatisfy { part in
            part.streams.contains { stream in
                stream.streamType == 2
                    && stream.selected == true
                    && (stream.channels ?? 0) > 2
            }
        }
    }

    var supportsSubtitleAutoSync: Bool {
        let media = item.media[source.mediaIndex]
        let parts: ArraySlice<PlexMediaPart>
        if source.partIndex >= 0, media.parts.indices.contains(source.partIndex) {
            parts = media.parts[source.partIndex...source.partIndex]
        } else {
            parts = media.parts[...]
        }
        guard !parts.isEmpty else { return false }

        return parts.allSatisfy { part in
            part.streams.contains { stream in
                stream.streamType == 3
                    && stream.selected == true
                    && stream.canAutoSync == true
            }
        }
    }

    var queryItems: [URLQueryItem] {
        let media = item.media[source.mediaIndex]
        let isVideo = media.videoCodec?.nilIfBlank != nil
        let limitsVideoQuality = videoQuality.limits(media: media)
        let limitsMusicQuality = musicQuality.limits(media: media)
        let allowsDirectStream = streamingPolicy.allowsDirectStream
            && !limitsVideoQuality
            && !limitsMusicQuality
            && permitsOriginalVideoQuality
            && !forcesVideoTranscode
        let allowsDirectStreamAudio = streamingPolicy.allowsDirectStream
            && !limitsMusicQuality
            && (!isVideo || !automaticallyAdjustVideoQuality || allowsDirectStream)
        let subtitleValues = subtitleBurnMode.requestValues
        var items = [
            URLQueryItem(name: "path", value: "/library/metadata/\(item.ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: String(source.mediaIndex)),
            URLQueryItem(name: "partIndex", value: String(source.partIndex)),
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "directPlay", value: permitsDirectPlay ? "1" : "0"),
            URLQueryItem(name: "directStream", value: allowsDirectStream ? "1" : "0"),
            URLQueryItem(
                name: "directStreamAudio",
                value: allowsDirectStreamAudio ? "1" : "0"
            ),
            URLQueryItem(name: "subtitles", value: subtitleValues.subtitles),
            URLQueryItem(
                name: "advancedSubtitles",
                value: subtitleValues.advancedSubtitles
            ),
            URLQueryItem(name: "offset", value: startTime.plexServerOffset),
            URLQueryItem(name: "session", value: sessionIdentifier)
        ]

        if media.videoCodec?.nilIfBlank != nil {
            items.append(URLQueryItem(
                name: "subtitleSize",
                value: String(subtitleSize.rawValue)
            ))
            items.append(URLQueryItem(
                name: "autoAdjustSubtitle",
                value: automaticallySyncSubtitles && supportsSubtitleAutoSync ? "1" : "0"
            ))
            items.append(URLQueryItem(
                name: "audioBoost",
                value: String(audioBoost.rawValue)
            ))
            items.append(URLQueryItem(
                name: "autoAdjustQuality",
                value: automaticallyAdjustVideoQuality ? "1" : "0"
            ))
            appendVideoQualityItems(to: &items, media: media)
        } else if media.audioCodec?.nilIfBlank != nil {
            let bitrate = musicQuality.bitrate ?? media.bitrate
            if let bitrate, bitrate > 0 {
                items.append(URLQueryItem(name: "musicBitrate", value: String(bitrate)))
            }
        }

        return items
    }

    private var permitsOriginalVideoQuality: Bool {
        let media = item.media[source.mediaIndex]
        guard media.videoCodec?.nilIfBlank != nil, videoQuality != .original else {
            return true
        }
        return playSmallerVideosAtOriginalQuality
    }

    private var forcesVideoTranscode: Bool {
        forceVideoTranscode
            && item.media[source.mediaIndex].videoCodec?.nilIfBlank != nil
    }

    private func appendVideoQualityItems(
        to items: inout [URLQueryItem],
        media: PlexMediaVersion
    ) {
        items.append(URLQueryItem(name: "videoQuality", value: "99"))
        let resolution = videoQuality.constraints.map { ($0.width, $0.height) }
            ?? sourceResolution(for: media)
        // A source's average bitrate is not a playback bandwidth limit. Sending
        // it as a conversion target can make PMS downscale even at Original.
        let bitrate = videoQuality.constraints?.bitrate

        if let resolution {
            items.append(
                URLQueryItem(
                    name: "videoResolution",
                    value: "\(resolution.0)x\(resolution.1)"
                )
            )
        }
        if let bitrate, bitrate > 0 {
            items.append(URLQueryItem(name: "videoBitrate", value: String(bitrate)))
        }
    }

    private func sourceResolution(for media: PlexMediaVersion) -> (Int, Int)? {
        guard let width = media.width, width > 0,
              let height = media.height, height > 0 else {
            return nil
        }

        return (width, height)
    }
}

private extension PlexVideoQuality {
    func limits(media: PlexMediaVersion) -> Bool {
        guard media.videoCodec?.nilIfBlank != nil, let constraints else {
            return false
        }
        guard let width = media.width, width > 0,
              let height = media.height, height > 0,
              let bitrate = media.bitrate, bitrate > 0 else {
            return true
        }
        return width > constraints.width
            || height > constraints.height
            || bitrate > constraints.bitrate
    }
}

private extension TimeInterval {
    var plexServerOffset: String {
        let milliseconds = (max(isFinite ? self : 0, 0) * 1_000).rounded()
        guard milliseconds.truncatingRemainder(dividingBy: 1_000) != 0 else {
            return String(Int(milliseconds / 1_000))
        }

        var value = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            milliseconds / 1_000
        )
        while value.last == "0" {
            value.removeLast()
        }
        return value
    }
}
