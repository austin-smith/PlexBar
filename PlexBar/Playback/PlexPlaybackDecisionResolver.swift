import PlexModels
import Foundation

struct PlexPlaybackSelection: Equatable, Sendable {
    let method: PlexPlaybackPlan.Method
    let path: String
    let supportsAudioBoost: Bool

    init(
        method: PlexPlaybackPlan.Method,
        path: String,
        supportsAudioBoost: Bool = false
    ) {
        self.method = method
        self.path = path
        self.supportsAudioBoost = supportsAudioBoost
    }
}

enum PlexPlaybackDecisionResolution: Equatable, Sendable {
    case selected(PlexPlaybackSelection)
    case rejected(String)
    case noPlayableMedia
}

enum PlexPlaybackDecisionResolver {
    static func resolve(
        _ decision: PlexPlaybackDecisionContainer,
        mediaKind: PlexPlaybackMediaKind
    ) -> PlexPlaybackDecisionResolution {
        if let code = decision.generalDecisionCode,
           !(1_000..<2_000).contains(code) {
            return .rejected(decision.generalDecisionText ?? "decision code \(code)")
        }

        guard let item = decision.metadata.first,
              let media = item.media.first(where: { $0.selected == true }) ?? item.media.first,
              let part = media.parts.first(where: { $0.selected == true }) ?? media.parts.first else {
            return .noPlayableMedia
        }

        if part.decision?.lowercased() == "directplay", let key = part.key?.nilIfBlank {
            return .selected(PlexPlaybackSelection(method: .directPlay, path: key))
        }

        let transcodes = part.streams.contains { stream in
            ["transcode", "burn"].contains(stream.decision?.lowercased())
        }
        let supportsAudioBoost = part.streams.contains { stream in
            stream.streamType == 2
                && ["transcode", "burn"].contains(stream.decision?.lowercased())
                && stream.channels == 2
        }
        return .selected(PlexPlaybackSelection(
            method: transcodes ? .transcode : .directStream,
            path: mediaKind.startPath,
            supportsAudioBoost: supportsAudioBoost
        ))
    }
}
