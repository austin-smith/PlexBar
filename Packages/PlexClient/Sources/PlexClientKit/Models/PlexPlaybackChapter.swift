import PlexModels
import Foundation

public struct PlexPlaybackChapter: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let thumbnailPath: String?

    public static func chapters(
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

    public init(
        id: String,
        title: String,
        startTime: TimeInterval,
        duration: TimeInterval,
        thumbnailPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.duration = duration
        self.thumbnailPath = thumbnailPath
    }
}
