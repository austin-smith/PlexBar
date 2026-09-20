import PlexClientKit
import Foundation
import PlexModels

enum PlexPlaybackPreviewSource: Equatable, Sendable {
    case server(PlexServerPlaybackPreviewSource)
    case unavailable(String)
}

struct PlexServerPlaybackPreviewSource: Equatable, Sendable {
    let serverURL: URL
    let token: String
    let clientContext: PlexClientContext
    let sessionIdentifier: String
    let parts: [PlexMediaPart]

    /// A single selected part uses its own timeline. Concatenated parts use
    /// declared durations to translate the player's timeline into a part offset.
    func frame(at seconds: TimeInterval) throws -> PlexPlaybackPreviewFrame {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max / 1_000),
              !parts.isEmpty else {
            throw PlexPlaybackPreviewError.invalidTimeline
        }
        var offset = Int(seconds * 1_000)
        for (index, part) in parts.enumerated() {
            if parts.count > 1 {
                guard let duration = part.duration, duration > 0 else {
                    throw PlexPlaybackPreviewError.invalidTimeline
                }
                if offset >= duration, index < parts.count - 1 {
                    offset -= duration
                    continue
                }
                guard offset <= duration else { throw PlexPlaybackPreviewError.invalidTimeline }
            }
            guard let id = part.id, id > 0 else { throw PlexPlaybackPreviewError.invalidTimeline }
            guard part.indexes?.split(separator: ",").contains("sd") == true else {
                throw PlexPlaybackPreviewError.noIndex
            }
            if let duration = part.duration, duration > 0 {
                offset = min(offset, duration - 1)
            }
            // One-second request buckets bound cache growth independently of
            // pointer event frequency. PMS selects the indexed image for this time.
            return PlexPlaybackPreviewFrame(partID: id, partKey: part.key, offsetMilliseconds: offset / 1_000 * 1_000)
        }
        throw PlexPlaybackPreviewError.invalidTimeline
    }
}

struct PlexPlaybackPreviewFrame: Hashable, Sendable {
    let partID: Int
    let partKey: String?
    let offsetMilliseconds: Int

    var path: String { "/library/parts/\(partID)/indexes/sd/\(offsetMilliseconds)" }
    var cacheKey: String { "\(partID)|\(partKey ?? "")|\(offsetMilliseconds)" }
}

enum PlexPlaybackPreviewError: Error, Equatable, LocalizedError {
    case noIndex
    case invalidTimeline
    case invalidResponse
    case httpStatus(Int)
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .noIndex: "No video previews for this video"
        case .invalidTimeline: "Preview timing is unavailable"
        case .invalidResponse: "Invalid preview response"
        case .httpStatus(let status): "Preview request failed (HTTP \(status))"
        case .invalidImage: "The server returned an invalid preview image"
        }
    }
}
