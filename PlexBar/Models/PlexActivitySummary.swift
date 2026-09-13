import Foundation

enum PlexSessionDeliveryMethod: CaseIterable {
    case directPlay
    case directStream
    case transcoding
    case unknown
}

struct PlexActivitySummary {
    let streamCount: Int
    private(set) var directPlayCount = 0
    private(set) var directStreamCount = 0
    private(set) var transcodingCount = 0
    private(set) var unknownCount = 0
    private(set) var reportedBandwidthCount = 0
    private(set) var totalBandwidthKbps: Double = 0
    private(set) var localBandwidthKbps: Double = 0
    private(set) var remoteBandwidthKbps: Double = 0
    private(set) var unknownLocationBandwidthKbps: Double = 0
    private(set) var unknownLocationCount = 0

    var hasPartialBandwidth: Bool {
        reportedBandwidthCount > 0 && reportedBandwidthCount < streamCount
    }

    // The store owns canonical session identity and deduplication.
    init(sessions: [PlexSession]) {
        streamCount = sessions.count
        for session in sessions {
            switch session.deliveryMethod {
            case .directPlay: directPlayCount += 1
            case .directStream: directStreamCount += 1
            case .transcoding: transcodingCount += 1
            case .unknown: unknownCount += 1
            }

            guard let bandwidth = session.session?.bandwidth, bandwidth >= 0 else { continue }
            reportedBandwidthCount += 1
            let value = Double(bandwidth)
            totalBandwidthKbps += value
            switch session.session?.location?.lowercased() {
            case "lan": localBandwidthKbps += value
            case "wan": remoteBandwidthKbps += value
            default:
                unknownLocationBandwidthKbps += value
                unknownLocationCount += 1
            }
        }
    }

    static func bandwidthText(kbps: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let mbps = kbps / 1_000
        let format = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...1))
            .rounded(rule: .toNearestOrAwayFromZero)
            .locale(locale)
        if mbps > 0 && mbps < 0.05 {
            return "<\(0.1.formatted(format)) Mbps"
        }
        return "\(mbps.formatted(format)) Mbps"
    }
}

extension PlexSession {
    var deliveryMethod: PlexSessionDeliveryMethod {
        // Live TV exposes its output decisions on TranscodeSession rather than
        // necessarily on the source tracks (the same distinction Tautulli uses).
        if isLive, let transcodeSession {
            let decisions = [transcodeSession.videoDecision, transcodeSession.audioDecision]
                .compactMap { $0?.nilIfBlank?.lowercased() }
            return Self.deliveryMethod(for: decisions)
        }

        guard let activePart = activePlaybackPart else {
            return .unknown
        }

        let partDecision = activePart.decision?.nilIfBlank?.lowercased()
        // Direct play applies to the whole part. Its source can list multiple
        // audio/subtitle tracks without identifying which the client selected.
        if partDecision == "directplay" { return .directPlay }
        guard partDecision == nil || partDecision == "transcode" else { return .unknown }

        var decisions: [String] = []
        for type in [1, 2] {
            let candidates = (activePart.stream ?? []).filter {
                $0.streamType == type && $0.selected != false
            }
            guard !candidates.isEmpty else { continue }
            guard let stream = Self.activeItem(in: candidates, selected: \.selected) else {
                return .unknown
            }
            // Plex omits the decision for direct-play tracks. Subtitle conversion
            // does not determine whether the audio/video is transcoding.
            decisions.append(stream.decision?.nilIfBlank?.lowercased() ?? "directplay")
        }
        // A transcode part without any audio/video conversion decision is incomplete.
        if partDecision == "transcode", decisions.allSatisfy({ $0 == "directplay" }) {
            return .unknown
        }
        return Self.deliveryMethod(for: decisions)
    }

    private static func deliveryMethod(for decisions: [String]) -> PlexSessionDeliveryMethod {
        guard !decisions.isEmpty,
              decisions.allSatisfy({ ["directplay", "direct play", "copy", "transcode"].contains($0) }) else {
            return .unknown
        }
        if decisions.contains("transcode") { return .transcoding }
        if decisions.contains("copy") { return .directStream }
        return .directPlay
    }

    var activePlaybackPart: PlexPart? {
        guard let media = Self.activeItem(in: media ?? [], selected: \.selected) else { return nil }
        return Self.activeItem(in: media.part ?? [], selected: \.selected)
    }

    func activePlaybackStream(type: Int) -> PlexStream? {
        let candidates = (activePlaybackPart?.stream ?? []).filter {
            $0.streamType == type && $0.selected != false
                && (type != 3 || $0.selected == true || $0.decision?.nilIfBlank != nil)
                && $0.decision?.lowercased() != "ignore"
                && $0.decision?.lowercased() != "none"
        }
        return Self.activeItem(in: candidates, selected: \.selected)
    }

    private static func activeItem<Item>(in items: [Item], selected: KeyPath<Item, Bool?>) -> Item? {
        let explicit = items.filter { $0[keyPath: selected] == true }
        if explicit.count == 1 { return explicit[0] }
        guard explicit.isEmpty else { return nil }
        let eligible = items.filter { $0[keyPath: selected] != false }
        return eligible.count == 1 ? eligible[0] : nil
    }
}
