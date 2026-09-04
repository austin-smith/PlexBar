import Foundation

struct PlexPlaybackRequestParameters {
    let item: PlexMediaItem
    let source: PlexPlaybackSource
    let videoQuality: PlexVideoQuality
    let streamingPolicy: PlexPlaybackStreamingPolicy
    let sessionIdentifier: String
    let startTime: TimeInterval
    let forceServerMediaSelection: Bool

    var permitsDirectPlay: Bool {
        streamingPolicy.allowsDirectPlay
            && !videoQuality.limits(media: item.media[source.mediaIndex])
            && !forceServerMediaSelection
    }

    var queryItems: [URLQueryItem] {
        let media = item.media[source.mediaIndex]
        let limitsVideoQuality = videoQuality.limits(media: media)
        let allowsDirectStream = streamingPolicy.allowsDirectStream && !limitsVideoQuality
        var items = [
            URLQueryItem(name: "path", value: "/library/metadata/\(item.ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: String(source.mediaIndex)),
            URLQueryItem(name: "partIndex", value: String(source.partIndex)),
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "directPlay", value: permitsDirectPlay ? "1" : "0"),
            URLQueryItem(name: "directStream", value: allowsDirectStream ? "1" : "0"),
            URLQueryItem(
                name: "directStreamAudio",
                value: streamingPolicy.allowsDirectStream ? "1" : "0"
            ),
            URLQueryItem(name: "subtitles", value: "auto"),
            URLQueryItem(name: "offset", value: startTime.plexServerOffset),
            URLQueryItem(name: "session", value: sessionIdentifier)
        ]

        if media.videoCodec?.nilIfBlank != nil {
            appendVideoQualityItems(to: &items, media: media)
        } else if media.audioCodec?.nilIfBlank != nil,
                  let bitrate = media.bitrate, bitrate > 0 {
            items.append(URLQueryItem(name: "musicBitrate", value: String(bitrate)))
        }

        return items
    }

    private func appendVideoQualityItems(
        to items: inout [URLQueryItem],
        media: PlexMediaVersion
    ) {
        items.append(URLQueryItem(name: "videoQuality", value: "99"))
        let resolution = videoQuality.constraints.map { ($0.width, $0.height) }
            ?? sourceResolution(for: media)
        let bitrate = videoQuality.constraints?.bitrate ?? media.bitrate

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
