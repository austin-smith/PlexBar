import PlexModels
import Foundation

struct PlexSessionPlaybackDetails {
    struct Row: Identifiable {
        let title: String
        let source: String
        let output: String?
        var id: String { title }
    }

    let method: String
    let bandwidth: String?
    let usesHardware: Bool
    let rows: [Row]

    init(session: PlexSession) {
        switch session.deliveryMethod {
        case .directPlay: method = "Direct Play"
        case .directStream: method = "Direct Stream"
        case .transcoding: method = "Transcoding"
        case .unknown: method = "Unknown"
        }
        if let value = session.session?.bandwidth, value >= 0 {
            bandwidth = PlexActivitySummary.bandwidthText(kbps: Double(value))
        } else {
            bandwidth = nil
        }
        let transcode = session.transcodeSession
        usesHardware = session.deliveryMethod == .transcoding
            && transcode?.videoDecision?.lowercased() == "transcode"
            && [transcode?.transcodeHwDecoding, transcode?.transcodeHwEncoding].contains {
                guard let engine = $0?.nilIfBlank?.lowercased() else { return false }
                return engine != "none"
            }

        var details: [Row] = []
        for (type, title) in [(1, "Video"), (2, "Audio")] {
            let stream = session.activePlaybackStream(type: type)
            let sourceCodec = type == 1 ? transcode?.sourceVideoCodec : transcode?.sourceAudioCodec
            let outputCodec = type == 1 ? transcode?.videoCodec : transcode?.audioCodec
            let outputDecision = type == 1 ? transcode?.videoDecision : transcode?.audioDecision
            let hasTrack = session.activePlaybackPart?.stream?.contains { $0.streamType == type } == true
            guard hasTrack || outputCodec?.nilIfBlank != nil else { continue }

            let decision = session.isLive && transcode != nil ? outputDecision : stream?.decision
            let converting = decision?.lowercased() == "transcode"
            // Plex retains the source display title on the selected output stream.
            // When it is absent, never substitute the output codec for the source.
            let source = stream?.displayTitle?.nilIfBlank
                ?? Self.sourceDescription(language: type == 2 ? stream?.language : nil,
                                          codec: converting ? sourceCodec : stream?.codec)
                ?? "Unavailable"
            let bitrate = !session.isLive || stream?.decision?.lowercased() == decision?.lowercased()
                ? stream?.bitrate : nil
            let output = Self.outputDescription(decision: decision,
                                                codec: session.isLive ? outputCodec : stream?.codec ?? outputCodec,
                                                bitrate: bitrate, hardware: type == 1 && usesHardware)
            details.append(Row(title: title, source: source, output: output))
        }
        if details.isEmpty {
            details.append(Row(title: session.contentKind == .track ? "Audio" : "Video", source: "Unavailable", output: nil))
        }
        if session.contentKind != .track {
            if let subtitle = session.activePlaybackStream(type: 3) {
                let source = subtitle.displayTitle?.nilIfBlank
                    ?? Self.sourceDescription(language: subtitle.language,
                                              codec: subtitle.decision?.lowercased() == "transcode" ? nil : subtitle.codec)
                    ?? "Unavailable"
                let output: String?
                switch subtitle.decision?.lowercased() {
                case "burn": output = "Burn In"
                case "transcode": output = Self.codecName(subtitle.codec) ?? "Transcode"
                default: output = nil
                }
                details.append(Row(title: "Subtitles", source: source, output: output))
            } else {
                let hasSelectedSubtitle = session.activePlaybackPart?.stream?.contains { $0.streamType == 3 && $0.selected == true } == true
                details.append(Row(title: "Subtitles", source: session.activePlaybackPart == nil || hasSelectedSubtitle ? "Unavailable" : "None", output: nil))
            }
        }
        rows = details
    }

    private static func sourceDescription(language: String?, codec: String?) -> String? {
        [language?.nilIfBlank, codecName(codec)].compactMap { $0 }.joined(separator: " · ").nilIfBlank
    }

    private static func outputDescription(decision: String?, codec: String?, bitrate: Int?, hardware: Bool) -> String? {
        let description: String
        switch decision?.nilIfBlank?.lowercased() {
        case "transcode": description = codecName(codec) ?? "Transcode"
        case "copy": description = "Direct Stream"
        default: return nil
        }
        var pieces = [description]
        if let bitrate, bitrate > 0 { pieces.append(trackBitrateText(kbps: bitrate)) }
        if hardware { pieces.append("HW") }
        return pieces.joined(separator: " · ")
    }

    static func trackBitrateText(kbps: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let format = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...1))
            .locale(locale)
        if kbps < 1_000 { return "\(Double(kbps).formatted(format)) Kbps" }
        return "\((Double(kbps) / 1_000).formatted(format)) Mbps"
    }

    private static func codecName(_ codec: String?) -> String? {
        guard let codec = codec?.nilIfBlank, codec != "*" else { return nil }
        switch codec.lowercased() {
        case "h264": return "H.264"
        case "h265", "hevc": return "HEVC"
        default: return codec.uppercased()
        }
    }
}
