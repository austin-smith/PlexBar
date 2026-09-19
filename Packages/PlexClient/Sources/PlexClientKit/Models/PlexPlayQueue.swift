import PlexModels
import Foundation

public enum PlexContinuousPlayQueueType: String, Sendable {
    case audio
    case video
}

public enum PlexPlayQueueInsertion: Sendable {
    case next
    case upNext

    public var queryValue: String {
        switch self {
        case .next: "1"
        case .upNext: "0"
        }
    }
}

public enum PlexPlayQueueItemMoveDirection: Sendable {
    case up
    case down

    public var indexDelta: Int {
        switch self {
        case .up: -1
        case .down: 1
        }
    }
}

public struct PlexPlayQueueItemMove: Equatable, Sendable {
    public let playQueueItemID: String
    public let afterPlayQueueItemID: String

    public init(playQueueItemID: String, afterPlayQueueItemID: String) {
        self.playQueueItemID = playQueueItemID
        self.afterPlayQueueItemID = afterPlayQueueItemID
    }
}

public enum PlexPlaybackQueuePurpose: Equatable, Sendable {
    case standard
    case cinemaPreplay(primaryRatingKey: String)
}

extension PlexMediaItem {
    public var continuousPlayQueueType: PlexContinuousPlayQueueType? {
        switch type?.lowercased() {
        case "show", "season", "episode": .video
        case "track": .audio
        default: nil
        }
    }

    public var continuousPlayQueueUsesOnDeck: Bool {
        switch type?.lowercased() {
        case "show", "season": true
        default: false
        }
    }

    public var supportsHierarchyPlayback: Bool {
        continuousPlayQueueUsesOnDeck && key?.nilIfBlank?.hasPrefix("/") == true
    }

    public var queueablePlayQueueType: PlexContinuousPlayQueueType? {
        switch type?.lowercased() {
        case "movie", "show", "season", "episode", "clip": .video
        case "artist", "album", "track": .audio
        default:
            nil
        }
    }
}

public enum PlexPlaybackQueueDirection: Sendable {
    case previous
    case next

    public var indexDelta: Int {
        switch self {
        case .previous: -1
        case .next: 1
        }
    }
}

public struct PlexPlaybackQueue: Equatable, Sendable {
    public let id: Int
    public let purpose: PlexPlaybackQueuePurpose
    public private(set) var version: Int?
    public private(set) var totalCount: Int
    public private(set) var windowOffset: Int
    public private(set) var items: [PlexMediaItem]
    public private(set) var currentIndex: Int
    public private(set) var isShuffled: Bool
    public private(set) var hasUpNextRegion: Bool

    public init(
        page: PlexPlayQueuePage,
        selectedRatingKey: String,
        purpose: PlexPlaybackQueuePurpose = .standard
    ) throws {
        guard Self.hasStableUniqueQueueItemIDs(page.items) else {
            throw PlexAPIError.invalidPlayQueue
        }
        let selectedIndex = page.items.firstIndex {
            $0.playQueueItemID == page.selectedItemID
        } ?? page.items.firstIndex {
            $0.ratingKey == selectedRatingKey
        }
        guard let selectedIndex else {
            throw PlexAPIError.invalidPlayQueue
        }

        id = page.id
        self.purpose = purpose
        version = page.version
        items = page.items
        currentIndex = selectedIndex
        windowOffset = page.offset
            ?? page.selectedItemOffset.map { max($0 - selectedIndex, 0) }
            ?? 0
        totalCount = page.totalCount ?? max(windowOffset + page.items.count, page.items.count)
        isShuffled = page.isShuffled ?? false
        hasUpNextRegion = page.lastAddedItemID?.nilIfBlank != nil
    }

    public var currentItem: PlexMediaItem {
        items[currentIndex]
    }

    public var previousItem: PlexMediaItem? {
        let index = currentIndex - 1
        return items.indices.contains(index) ? items[index] : nil
    }

    public var nextItem: PlexMediaItem? {
        let index = currentIndex + 1
        return items.indices.contains(index) ? items[index] : nil
    }

    public var currentAbsoluteIndex: Int {
        windowOffset + currentIndex
    }

    public var presentation: PlexPlaybackQueuePresentation {
        let upcomingItems: [PlexMediaItem]
        if items.indices.contains(currentIndex + 1) {
            upcomingItems = Array(items[(currentIndex + 1)...])
        } else {
            upcomingItems = []
        }

        return PlexPlaybackQueuePresentation(
            currentItem: currentItem,
            upcomingItems: upcomingItems,
            currentPosition: currentAbsoluteIndex + 1,
            totalCount: totalCount,
            isShuffled: isShuffled,
            canRemoveUpcomingItems: purpose == .standard,
            canReorderUpcomingItems: canReorderLoadedUpcomingItems
        )
    }

    public var canMovePrevious: Bool {
        currentAbsoluteIndex > 0
    }

    public var canMoveNext: Bool {
        currentAbsoluteIndex + 1 < totalCount
    }

    public var canChangeShuffle: Bool {
        purpose == .standard && totalCount > 1 && !hasUpNextRegion
    }

    public var canRepeatAll: Bool {
        purpose == .standard && totalCount > 1
    }

    public var canReorderLoadedUpcomingItems: Bool {
        purpose == .standard && items.count - currentIndex - 1 > 1
    }

    public var isCurrentCinemaPreplayItem: Bool {
        guard case .cinemaPreplay(let primaryRatingKey) = purpose else {
            return false
        }
        return currentItem.ratingKey != primaryRatingKey
    }

    public var isCinemaPreplayQueue: Bool {
        if case .cinemaPreplay = purpose {
            return true
        }
        return false
    }

    public func canAdd(_ item: PlexMediaItem) -> Bool {
        guard purpose == .standard,
              item.key?.nilIfBlank?.hasPrefix("/") == true,
              let currentType = currentItem.queueablePlayQueueType else {
            return false
        }
        return item.queueablePlayQueueType == currentType
    }

    public func canRemoveUpcomingItem(playQueueItemID: String) -> Bool {
        guard purpose == .standard,
              let playQueueItemID = playQueueItemID.nilIfBlank else {
            return false
        }
        return items[(currentIndex + 1)...].contains {
            $0.playQueueItemID == playQueueItemID
        }
    }

    public func moveRequest(
        for playQueueItemID: String,
        direction: PlexPlayQueueItemMoveDirection
    ) -> PlexPlayQueueItemMove? {
        guard let playQueueItemID = playQueueItemID.nilIfBlank,
              let itemIndex = items.firstIndex(where: {
                  $0.playQueueItemID == playQueueItemID
              }), itemIndex > currentIndex else {
            return nil
        }

        let sourceIndex = itemIndex - currentIndex - 1
        let destinationIndex = sourceIndex + direction.indexDelta
        return moveRequest(
            for: playQueueItemID,
            toUpcomingIndex: destinationIndex
        )
    }

    public func moveRequest(
        fromUpcomingOffsets sourceOffsets: IndexSet,
        toUpcomingOffset destinationOffset: Int
    ) -> PlexPlayQueueItemMove? {
        let upcomingCount = items.count - currentIndex - 1
        guard sourceOffsets.count == 1,
              let sourceIndex = sourceOffsets.first,
              (0..<upcomingCount).contains(sourceIndex),
              (0...upcomingCount).contains(destinationOffset) else {
            return nil
        }

        let destinationIndex = destinationOffset > sourceIndex
            ? destinationOffset - 1
            : destinationOffset
        guard destinationIndex != sourceIndex,
              (0..<upcomingCount).contains(destinationIndex),
              let playQueueItemID = items[currentIndex + 1 + sourceIndex]
                .playQueueItemID?.nilIfBlank else {
            return nil
        }
        return moveRequest(
            for: playQueueItemID,
            toUpcomingIndex: destinationIndex
        )
    }

    public func canApplyMoveRequest(_ request: PlexPlayQueueItemMove) -> Bool {
        guard purpose == .standard,
              let itemIndex = items.firstIndex(where: {
                  $0.playQueueItemID == request.playQueueItemID
              }),
              let afterIndex = items.firstIndex(where: {
                  $0.playQueueItemID == request.afterPlayQueueItemID
              }),
              itemIndex > currentIndex,
              afterIndex >= currentIndex,
              itemIndex != afterIndex,
              let currentPredecessorID = items[itemIndex - 1]
                .playQueueItemID?.nilIfBlank else {
            return false
        }
        return currentPredecessorID != request.afterPlayQueueItemID
    }

    private func moveRequest(
        for playQueueItemID: String,
        toUpcomingIndex destinationIndex: Int
    ) -> PlexPlayQueueItemMove? {
        let upcomingItems = Array(items.dropFirst(currentIndex + 1))
        guard purpose == .standard,
              let playQueueItemID = playQueueItemID.nilIfBlank,
              let sourceIndex = upcomingItems.firstIndex(where: {
                  $0.playQueueItemID == playQueueItemID
              }),
              upcomingItems.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return nil
        }

        var reorderedItems = upcomingItems
        let movedItem = reorderedItems.remove(at: sourceIndex)
        reorderedItems.insert(movedItem, at: destinationIndex)
        let predecessor = destinationIndex == 0
            ? currentItem
            : reorderedItems[destinationIndex - 1]

        guard let afterPlayQueueItemID = predecessor.playQueueItemID?.nilIfBlank else {
            return nil
        }
        return PlexPlayQueueItemMove(
            playQueueItemID: playQueueItemID,
            afterPlayQueueItemID: afterPlayQueueItemID
        )
    }

    public func canMove(_ direction: PlexPlaybackQueueDirection) -> Bool {
        switch direction {
        case .previous: canMovePrevious
        case .next: canMoveNext
        }
    }

    public func needsWindowRefresh(for direction: PlexPlaybackQueueDirection) -> Bool {
        guard canMove(direction) else {
            return false
        }
        return !items.indices.contains(currentIndex + direction.indexDelta)
    }

    public mutating func move(_ direction: PlexPlaybackQueueDirection) -> PlexMediaItem? {
        guard canMove(direction) else {
            return nil
        }
        let destination = currentIndex + direction.indexDelta
        guard items.indices.contains(destination) else {
            return nil
        }
        currentIndex = destination
        return currentItem
    }

    public mutating func move(toPlayQueueItemID playQueueItemID: String) -> PlexMediaItem? {
        guard let destination = items.firstIndex(where: {
            $0.playQueueItemID == playQueueItemID
        }), destination != currentIndex else {
            return nil
        }
        currentIndex = destination
        return currentItem
    }

    public mutating func replaceWindow(
        with page: PlexPlayQueuePage,
        centeredOn playQueueItemID: String
    ) throws {
        guard page.id == id,
              Self.hasStableUniqueQueueItemIDs(page.items),
              let centeredIndex = page.items.firstIndex(where: {
                  $0.playQueueItemID == playQueueItemID
              }) else {
            throw PlexAPIError.invalidPlayQueue
        }

        let absoluteIndex = currentAbsoluteIndex
        version = page.version
        totalCount = page.totalCount ?? totalCount
        items = page.items
        currentIndex = centeredIndex
        windowOffset = page.offset ?? max(absoluteIndex - centeredIndex, 0)
        if let isShuffled = page.isShuffled {
            self.isShuffled = isShuffled
        }
        hasUpNextRegion = page.lastAddedItemID?.nilIfBlank != nil
    }

    private static func hasStableUniqueQueueItemIDs(
        _ items: [PlexMediaItem]
    ) -> Bool {
        let queueItemIDs = items.compactMap {
            $0.playQueueItemID?.nilIfBlank
        }
        return queueItemIDs.count == items.count
            && Set(queueItemIDs).count == queueItemIDs.count
    }

    public mutating func applyShuffleMutation(
        _ page: PlexPlayQueuePage,
        expectedShuffled: Bool
    ) throws {
        guard page.id == id,
              page.isShuffled == expectedShuffled,
              let currentPlayQueueItemID = currentItem.playQueueItemID else {
            throw PlexAPIError.invalidPlayQueue
        }

        let replacement = try PlexPlaybackQueue(
            page: page,
            selectedRatingKey: currentItem.ratingKey,
            purpose: purpose
        )
        guard replacement.currentItem.playQueueItemID == currentPlayQueueItemID else {
            throw PlexAPIError.invalidPlayQueue
        }
        self = replacement
    }

    public mutating func applyReset(_ page: PlexPlayQueuePage) throws {
        guard page.id == id,
              let selectedItemID = page.selectedItemID?.nilIfBlank,
              page.selectedItemOffset == 0 else {
            throw PlexAPIError.invalidPlayQueue
        }

        let replacement = try PlexPlaybackQueue(
            page: page,
            selectedRatingKey: currentItem.ratingKey,
            purpose: purpose
        )
        guard replacement.currentAbsoluteIndex == 0,
              replacement.currentItem.playQueueItemID == selectedItemID else {
            throw PlexAPIError.invalidPlayQueue
        }
        self = replacement
    }

    public mutating func applyAddition(_ page: PlexPlayQueuePage) throws {
        guard page.id == id,
              let currentPlayQueueItemID = currentItem.playQueueItemID?.nilIfBlank,
              page.selectedItemID?.nilIfBlank == currentPlayQueueItemID else {
            throw PlexAPIError.invalidPlayQueue
        }

        let replacement = try PlexPlaybackQueue(
            page: page,
            selectedRatingKey: currentItem.ratingKey,
            purpose: purpose
        )
        guard replacement.currentItem.playQueueItemID == currentPlayQueueItemID else {
            throw PlexAPIError.invalidPlayQueue
        }
        self = replacement
    }

    public mutating func applyRemoval(
        _ page: PlexPlayQueuePage,
        removedPlayQueueItemID: String
    ) throws {
        guard canRemoveUpcomingItem(playQueueItemID: removedPlayQueueItemID),
              let currentPlayQueueItemID = currentItem.playQueueItemID?.nilIfBlank else {
            throw PlexAPIError.invalidPlayQueue
        }

        let replacement = try mutationReplacement(
            from: page,
            currentPlayQueueItemID: currentPlayQueueItemID,
            fallbackTotalCount: max(totalCount - 1, 1)
        )
        guard !replacement.items.contains(where: {
            $0.playQueueItemID == removedPlayQueueItemID
        }) else {
            throw PlexAPIError.invalidPlayQueue
        }
        self = replacement
    }

    public mutating func applyMove(
        _ page: PlexPlayQueuePage,
        request: PlexPlayQueueItemMove
    ) throws {
        guard canApplyMoveRequest(request),
              let currentPlayQueueItemID = currentItem.playQueueItemID?.nilIfBlank else {
            throw PlexAPIError.invalidPlayQueue
        }

        let replacement = try mutationReplacement(
            from: page,
            currentPlayQueueItemID: currentPlayQueueItemID,
            fallbackTotalCount: totalCount
        )
        guard let movedIndex = replacement.items.firstIndex(where: {
            $0.playQueueItemID == request.playQueueItemID
        }),
        let afterIndex = replacement.items.firstIndex(where: {
            $0.playQueueItemID == request.afterPlayQueueItemID
        }),
        movedIndex == afterIndex + 1,
        movedIndex > replacement.currentIndex else {
            throw PlexAPIError.invalidPlayQueue
        }
        self = replacement
    }

    private func mutationReplacement(
        from page: PlexPlayQueuePage,
        currentPlayQueueItemID: String,
        fallbackTotalCount: Int
    ) throws -> PlexPlaybackQueue {
        guard page.id == id,
              page.selectedItemID?.nilIfBlank == currentPlayQueueItemID,
              version == nil || page.version == nil || page.version! > version! else {
            throw PlexAPIError.invalidPlayQueue
        }

        let normalizedPage = PlexPlayQueuePage(
            id: page.id,
            version: page.version,
            totalCount: page.totalCount ?? fallbackTotalCount,
            offset: page.offset,
            selectedItemID: page.selectedItemID,
            selectedItemOffset: page.selectedItemOffset ?? currentAbsoluteIndex,
            items: page.items,
            isShuffled: page.isShuffled ?? isShuffled,
            lastAddedItemID: page.lastAddedItemID
        )
        let replacement = try PlexPlaybackQueue(
            page: normalizedPage,
            selectedRatingKey: currentItem.ratingKey,
            purpose: purpose
        )
        guard replacement.currentItem.playQueueItemID == currentPlayQueueItemID else {
            throw PlexAPIError.invalidPlayQueue
        }
        return replacement
    }
}

public struct PlexPlaybackQueuePresentation: Equatable, Sendable {
    public let currentItem: PlexMediaItem
    public let upcomingItems: [PlexMediaItem]
    public let currentPosition: Int
    public let totalCount: Int
    public let isShuffled: Bool
    public let canRemoveUpcomingItems: Bool
    public let canReorderUpcomingItems: Bool

    public var remainingCount: Int {
        max(totalCount - currentPosition, 0)
    }

    public var unloadedRemainingCount: Int {
        max(remainingCount - upcomingItems.count, 0)
    }

    public func canMoveUpcomingItem(
        playQueueItemID: String,
        direction: PlexPlayQueueItemMoveDirection
    ) -> Bool {
        guard canReorderUpcomingItems,
              let index = upcomingItems.firstIndex(where: {
                  $0.playQueueItemID == playQueueItemID
              }) else {
            return false
        }
        return upcomingItems.indices.contains(index + direction.indexDelta)
    }

    public init(
        currentItem: PlexMediaItem,
        upcomingItems: [PlexMediaItem],
        currentPosition: Int,
        totalCount: Int,
        isShuffled: Bool,
        canRemoveUpcomingItems: Bool,
        canReorderUpcomingItems: Bool
    ) {
        self.currentItem = currentItem
        self.upcomingItems = upcomingItems
        self.currentPosition = currentPosition
        self.totalCount = totalCount
        self.isShuffled = isShuffled
        self.canRemoveUpcomingItems = canRemoveUpcomingItems
        self.canReorderUpcomingItems = canReorderUpcomingItems
    }
}

public struct PlexPlayQueuePage: Equatable, Sendable {
    public let id: Int
    public let version: Int?
    public let totalCount: Int?
    public let offset: Int?
    public let selectedItemID: String?
    public let selectedItemOffset: Int?
    public let items: [PlexMediaItem]
    public let isShuffled: Bool?
    public let lastAddedItemID: String?

    public init(
        id: Int,
        version: Int?,
        totalCount: Int?,
        offset: Int?,
        selectedItemID: String?,
        selectedItemOffset: Int?,
        items: [PlexMediaItem],
        isShuffled: Bool? = nil,
        lastAddedItemID: String? = nil
    ) {
        self.id = id
        self.version = version
        self.totalCount = totalCount
        self.offset = offset
        self.selectedItemID = selectedItemID
        self.selectedItemOffset = selectedItemOffset
        self.items = items
        self.isShuffled = isShuffled
        self.lastAddedItemID = lastAddedItemID
    }
}

public struct PlexPlayQueueEnvelope: Decodable, Sendable {
    public let mediaContainer: PlexPlayQueueContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    public init(mediaContainer: PlexPlayQueueContainer) {
        self.mediaContainer = mediaContainer
    }
}

public struct PlexPlayQueueContainer: Decodable, Sendable {
    public let playQueueID: Int?
    public let playQueueVersion: Int?
    public let playQueueTotalCount: Int?
    public let playQueueSelectedItemID: String?
    public let playQueueSelectedItemOffset: Int?
    public let playQueueShuffled: Bool?
    public let playQueueLastAddedItemID: String?
    public let offset: Int?
    public let metadata: [PlexMediaItem]

    private enum CodingKeys: String, CodingKey {
        case playQueueID
        case playQueueVersion
        case playQueueTotalCount
        case playQueueSelectedItemID
        case playQueueSelectedItemOffset
        case playQueueShuffled
        case playQueueLastAddedItemID
        case offset
        case metadata = "Metadata"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        playQueueID = values.decodePlexIntIfPresent(forKey: .playQueueID)
        playQueueVersion = values.decodePlexIntIfPresent(forKey: .playQueueVersion)
        playQueueTotalCount = values.decodePlexIntIfPresent(forKey: .playQueueTotalCount)
        playQueueSelectedItemID = values.decodePlexStringIfPresent(forKey: .playQueueSelectedItemID)
        playQueueSelectedItemOffset = values.decodePlexIntIfPresent(forKey: .playQueueSelectedItemOffset)
        playQueueShuffled = values.decodePlexBoolIfPresent(forKey: .playQueueShuffled)
        playQueueLastAddedItemID = values.decodePlexStringIfPresent(
            forKey: .playQueueLastAddedItemID
        )
        offset = values.decodePlexIntIfPresent(forKey: .offset)
        metadata = try values.decodeIfPresent([PlexMediaItem].self, forKey: .metadata) ?? []
    }

    public func page() throws -> PlexPlayQueuePage {
        guard let playQueueID, !metadata.isEmpty else {
            throw PlexAPIError.invalidPlayQueue
        }
        return PlexPlayQueuePage(
            id: playQueueID,
            version: playQueueVersion,
            totalCount: playQueueTotalCount,
            offset: offset,
            selectedItemID: playQueueSelectedItemID,
            selectedItemOffset: playQueueSelectedItemOffset,
            items: metadata,
            isShuffled: playQueueShuffled,
            lastAddedItemID: playQueueLastAddedItemID
        )
    }
}
