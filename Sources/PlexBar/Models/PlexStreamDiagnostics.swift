import Foundation

struct PlexStreamDiagnostics: Equatable {
    struct Item: Identifiable, Equatable {
        let label: String
        let value: String
        let symbolName: String
        let isWarning: Bool

        var id: String {
            "\(label):\(value)"
        }
    }

    let playbackItems: [Item]
    let streamItems: [Item]
    let connectionItems: [Item]
    let decisionItem: Item?
    let mediaRows: [Item]
    let connectionRows: [Item]

    init(session: PlexSession) {
        let media = session.media?.first
        let part = media?.part?.first
        let streams = media?.part?.flatMap { $0.stream ?? [] } ?? []
        let videoStream = streams.first(where: { $0.isVideo && $0.selected == true }) ?? streams.first(where: \.isVideo)
        let audioStream = streams.first(where: { $0.isAudio && $0.selected == true }) ?? streams.first(where: \.isAudio)
        let subtitleStream = streams.first(where: { $0.isSubtitle && $0.selected == true }) ?? streams.first(where: \.isSubtitle)

        let decision = Self.formatDecision(part?.decision)
        let location = session.session?.location?.nilIfBlank?.uppercased()
        let bandwidth = Self.formatBandwidth(session.session?.bandwidth)
        let route = Self.routeDisplayName(local: session.player.local, relayed: session.player.relayed)
        let security = Self.securityDisplayName(session.player.secure)
        let videoCodec = Self.formatCodec(videoStream?.codec ?? part?.videoCodec ?? media?.videoCodec)
        let audioCodec = Self.formatCodec(audioStream?.codec ?? part?.audioCodec ?? media?.audioCodec)
        let resolution = Self.formatResolution(
            width: videoStream?.width ?? part?.width ?? media?.width,
            height: videoStream?.height ?? part?.height ?? media?.height
        )
        let bitrate = Self.formatBitrate(videoStream?.bitrate ?? audioStream?.bitrate ?? part?.bitrate ?? media?.bitrate)
        let videoSummary = Self.formatVideoSummary(resolution: resolution, codec: videoCodec, bitrate: Self.formatBitrate(videoStream?.bitrate ?? part?.bitrate ?? media?.bitrate))
        let audioSummary = Self.formatAudioSummary(stream: audioStream, codec: audioCodec)
        let subtitleSummary = Self.formatSubtitleSummary(stream: subtitleStream)

        decisionItem = decision.map { Item(label: "Stream", value: $0, symbolName: Self.decisionSymbol(for: $0), isWarning: false) }
        playbackItems = [decisionItem].compactMap { $0 }

        streamItems = [
            videoSummary.map { Item(label: "Video", value: $0, symbolName: "film", isWarning: false) },
            audioSummary.map { Item(label: "Audio", value: $0, symbolName: "waveform", isWarning: false) },
            subtitleSummary.map { Item(label: "Subtitles", value: $0, symbolName: "captions.bubble", isWarning: false) },
            bitrate.map { Item(label: "Bitrate", value: $0, symbolName: "gauge.with.dots.needle.67percent", isWarning: false) },
        ].compactMap { $0 }

        connectionItems = [
            location.map { Item(label: "Network", value: $0, symbolName: "network", isWarning: false) },
            route.map { Item(label: "Route", value: $0, symbolName: $0 == "Relay" ? "exclamationmark.arrow.triangle.2.circlepath" : "point.3.connected.trianglepath.dotted", isWarning: $0 == "Relay") },
            security.map { Item(label: "Security", value: $0, symbolName: $0 == "Secure" ? "lock" : "lock.open", isWarning: $0 == "Insecure") },
            bandwidth.map { Item(label: "Bandwidth", value: $0, symbolName: "speedometer", isWarning: false) },
        ].compactMap { $0 }

        mediaRows = [
            videoSummary.map { Item(label: "Video", value: $0, symbolName: "film", isWarning: false) },
            audioSummary.map { Item(label: "Audio", value: $0, symbolName: "waveform", isWarning: false) },
            subtitleSummary.map { Item(label: "Subtitles", value: $0, symbolName: "captions.bubble", isWarning: false) },
        ].compactMap { $0 }
        connectionRows = connectionItems
    }

    static func formatDecision(_ rawValue: String?) -> String? {
        switch rawValue?.nilIfBlank?.lowercased() {
        case "directplay", "direct play":
            "Direct Play"
        case "directstream", "direct stream", "copy":
            "Direct Stream"
        case "transcode":
            "Transcode"
        case let value?:
            value.capitalized
        case nil:
            nil
        }
    }

    private static func decisionSymbol(for decision: String) -> String {
        switch decision {
        case "Direct Play":
            "play.circle"
        case "Direct Stream":
            "arrow.triangle.branch"
        case "Transcode":
            "arrow.triangle.2.circlepath"
        default:
            "play.square"
        }
    }

    private static func routeDisplayName(local: Bool?, relayed: Bool?) -> String? {
        if relayed == true {
            return "Relay"
        }

        if local == true {
            return "Local"
        }

        if local == false {
            return "Remote"
        }

        return nil
    }

    private static func securityDisplayName(_ secure: Bool?) -> String? {
        switch secure {
        case true:
            "Secure"
        case false:
            "Insecure"
        case nil:
            nil
        }
    }

    private static func formatCodec(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.nilIfBlank else {
            return nil
        }

        return rawValue.uppercased()
    }

    private static func formatResolution(width: Int?, height: Int?) -> String? {
        guard let width, let height, width > 0, height > 0 else {
            return nil
        }

        return "\(width)x\(height)"
    }

    private static func formatVideoSummary(resolution: String?, codec: String?, bitrate: String?) -> String? {
        let base = [resolution, codec].compactMap { $0?.nilIfBlank }.joined(separator: " ")
        guard !base.isEmpty else {
            return bitrate
        }

        guard let bitrate = bitrate?.nilIfBlank else {
            return base
        }

        return "\(base), \(bitrate)"
    }

    private static func formatAudioSummary(stream: PlexStream?, codec: String?) -> String? {
        let language = stream?.language?.nilIfBlank
        let codec = codec?.nilIfBlank
        let channels = formatChannels(stream?.channels)
        let bitrate = formatBitrate(stream?.bitrate)
        let base = [language, codec, channels].compactMap { $0 }.joined(separator: " ")
        guard !base.isEmpty else {
            return bitrate
        }

        guard let bitrate else {
            return base
        }

        return "\(base), \(bitrate)"
    }

    private static func formatSubtitleSummary(stream: PlexStream?) -> String? {
        guard let stream else {
            return nil
        }

        if let displayTitle = stream.displayTitle?.nilIfBlank {
            return displayTitle
        }

        let language = stream.language?.nilIfBlank
        let codec = formatCodec(stream.codec)
        let value = [language, codec].compactMap { $0 }.joined(separator: " ")
        return value.nilIfBlank
    }

    private static func formatChannels(_ value: Int?) -> String? {
        switch value {
        case 1:
            "Mono"
        case 2:
            "Stereo"
        case 6:
            "5.1"
        case 8:
            "7.1"
        case let value? where value > 0:
            "\(value)ch"
        default:
            nil
        }
    }

    private static func formatBandwidth(_ value: Int?) -> String? {
        guard let value, value > 0 else {
            return nil
        }

        return formatMegabits(value)
    }

    private static func formatBitrate(_ value: Int?) -> String? {
        guard let value, value > 0 else {
            return nil
        }

        if value < 1000 {
            return "\(value) Kbps"
        }

        return formatMegabits(value)
    }

    private static func formatMegabits(_ value: Int) -> String {
        let megabits = Double(value) / 1000

        if megabits >= 10 {
            return "\(Int(megabits.rounded())) Mbps"
        }

        let formatted = String(format: "%.1f", megabits)
        return "\(formatted) Mbps"
    }
}
