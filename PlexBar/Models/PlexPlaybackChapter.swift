import Foundation

struct PlexMediaChapter: Decodable, Equatable, Hashable, Sendable {
    let id: String?
    let index: Int?
    let startTimeOffset: Int?
    let endTimeOffset: Int?
    let title: String?
    let thumb: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case index
        case startTimeOffset
        case endTimeOffset
        case title
        case thumb
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexStringIfPresent(forKey: .id)
        index = values.decodePlexIntIfPresent(forKey: .index)
        startTimeOffset = values.decodePlexIntIfPresent(forKey: .startTimeOffset)
        endTimeOffset = values.decodePlexIntIfPresent(forKey: .endTimeOffset)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        thumb = try values.decodeIfPresent(String.self, forKey: .thumb)
    }
}

struct PlexPlaybackChapter: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let startTime: TimeInterval
    let duration: TimeInterval
    let thumbnailPath: String?

    static func chapters(
        from chapters: [PlexMediaChapter],
        mediaDurationMilliseconds: Int?
    ) -> [Self] {
        let mediaEnd = mediaDurationMilliseconds.flatMap { duration in
            duration > 0 ? TimeInterval(duration) / 1_000 : nil
        }

        let validChapters = chapters.compactMap { chapter -> SourceChapter? in
            guard let startMilliseconds = chapter.startTimeOffset,
                  let endMilliseconds = chapter.endTimeOffset,
                  startMilliseconds >= 0,
                  endMilliseconds > startMilliseconds else {
                return nil
            }

            let startTime = TimeInterval(startMilliseconds) / 1_000
            let serverEndTime = TimeInterval(endMilliseconds) / 1_000
            guard mediaEnd.map({ startTime < $0 }) ?? true else {
                return nil
            }
            let endTime = min(serverEndTime, mediaEnd ?? serverEndTime)
            guard endTime > startTime else {
                return nil
            }

            return SourceChapter(
                sourceID: chapter.id,
                index: chapter.index,
                title: chapter.title?.nilIfBlank,
                startTime: startTime,
                endTime: endTime,
                thumbnailPath: chapter.thumb?.nilIfBlank
            )
        }
        .sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            if lhs.index != rhs.index {
                return (lhs.index ?? .max) < (rhs.index ?? .max)
            }
            return (lhs.sourceID ?? "") < (rhs.sourceID ?? "")
        }

        return validChapters.enumerated().map { offset, chapter in
            let chapterNumber = chapter.index.flatMap { $0 > 0 ? $0 : nil } ?? offset + 1
            return Self(
                id: [
                    chapter.sourceID ?? "chapter",
                    String(chapterNumber),
                    String(Int(chapter.startTime * 1_000))
                ].joined(separator: ":"),
                title: chapter.title ?? "Chapter \(chapterNumber)",
                startTime: chapter.startTime,
                duration: chapter.endTime - chapter.startTime,
                thumbnailPath: chapter.thumbnailPath
            )
        }
    }

    private struct SourceChapter {
        let sourceID: String?
        let index: Int?
        let title: String?
        let startTime: TimeInterval
        let endTime: TimeInterval
        let thumbnailPath: String?
    }
}
