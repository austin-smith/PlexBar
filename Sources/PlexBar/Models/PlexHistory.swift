import Foundation

struct PlexHistorySeriesIdentity: Equatable {
    let id: String
    let title: String
    let posterPath: String?
}

struct PlexHistoryItem: Decodable, Identifiable {
    let historyKey: String?
    let key: String?
    let ratingKey: String?
    let title: String
    let type: String?
    let thumb: String?
    let parentThumb: String?
    let grandparentThumb: String?
    let art: String?
    let grandparentTitle: String?
    let parentTitle: String?
    let parentIndex: Int?
    let index: Int?
    let originallyAvailableAt: String?
    let viewedAt: Date?
    let accountID: Int?
    let deviceID: Int?

    enum CodingKeys: String, CodingKey {
        case historyKey
        case key
        case ratingKey
        case title
        case type
        case thumb
        case parentThumb
        case grandparentThumb
        case art
        case grandparentTitle
        case parentTitle
        case parentIndex
        case index
        case originallyAvailableAt
        case viewedAt
        case accountID
        case deviceID
    }

    init(
        historyKey: String?,
        key: String?,
        ratingKey: String?,
        title: String,
        type: String?,
        thumb: String?,
        parentThumb: String?,
        grandparentThumb: String?,
        art: String?,
        grandparentTitle: String?,
        parentTitle: String?,
        parentIndex: Int?,
        index: Int?,
        originallyAvailableAt: String?,
        viewedAt: Date?,
        accountID: Int?,
        deviceID: Int? = nil
    ) {
        self.historyKey = historyKey
        self.key = key
        self.ratingKey = ratingKey
        self.title = title
        self.type = type
        self.thumb = thumb
        self.parentThumb = parentThumb
        self.grandparentThumb = grandparentThumb
        self.art = art
        self.grandparentTitle = grandparentTitle
        self.parentTitle = parentTitle
        self.parentIndex = parentIndex
        self.index = index
        self.originallyAvailableAt = originallyAvailableAt
        self.viewedAt = viewedAt
        self.accountID = accountID
        self.deviceID = deviceID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        historyKey = try container.decodeIfPresent(String.self, forKey: .historyKey)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        ratingKey = try container.decodeIfPresent(String.self, forKey: .ratingKey)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
        parentThumb = try container.decodeIfPresent(String.self, forKey: .parentThumb)
        grandparentThumb = try container.decodeIfPresent(String.self, forKey: .grandparentThumb)
        art = try container.decodeIfPresent(String.self, forKey: .art)
        grandparentTitle = try container.decodeIfPresent(String.self, forKey: .grandparentTitle)
        parentTitle = try container.decodeIfPresent(String.self, forKey: .parentTitle)
        parentIndex = try container.decodeIfPresent(Int.self, forKey: .parentIndex)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        originallyAvailableAt = try container.decodeIfPresent(String.self, forKey: .originallyAvailableAt)
        accountID = try container.decodeIfPresent(Int.self, forKey: .accountID)
        deviceID = try container.decodeIfPresent(Int.self, forKey: .deviceID)

        if let viewedAtTimestamp = try container.decodeIfPresent(Double.self, forKey: .viewedAt) {
            viewedAt = Date(timeIntervalSince1970: viewedAtTimestamp)
        } else if let viewedAtTimestamp = try container.decodeIfPresent(Int.self, forKey: .viewedAt) {
            viewedAt = Date(timeIntervalSince1970: Double(viewedAtTimestamp))
        } else if let viewedAtTimestamp = try container.decodeIfPresent(String.self, forKey: .viewedAt).flatMap(Double.init) {
            viewedAt = Date(timeIntervalSince1970: viewedAtTimestamp)
        } else {
            viewedAt = nil
        }
    }

    var id: String {
        if let historyKey = historyKey?.nilIfBlank {
            return historyKey
        }

        let timestamp = viewedAt.map { String(Int($0.timeIntervalSince1970)) }
        return [ratingKey, key, title, timestamp]
            .compactMap { $0 }
            .compactMap(\.nilIfBlank)
            .joined(separator: ":")
    }

    var contentKind: PlexSessionContentKind {
        PlexSessionContentKind(type: type, live: false)
    }

    var episodeMetadataItemID: String? {
        guard contentKind == .tv else {
            return nil
        }

        return ratingKey?.nilIfBlank
    }

    var posterPath: String? {
        preferredPosterCandidates
            .compactMap { $0?.nilIfBlank }
            .first
    }

    var headline: String {
        switch contentKind {
        case .tv:
            grandparentTitle ?? title
        default:
            title
        }
    }

    var detailLine: String? {
        switch contentKind {
        case .tv:
            let pieces = [episodeCode, title.nilIfBlank].compactMap { $0 }
            return pieces.isEmpty ? nil : pieces.joined(separator: " • ")
        case .track:
            let pieces = [parentTitle?.nilIfBlank, title.nilIfBlank].compactMap { $0 }
            return pieces.isEmpty ? nil : pieces.joined(separator: " • ")
        case .movie:
            return releaseYear ?? "Movie"
        default:
            return parentTitle?.nilIfBlank
        }
    }

    var viewedAtRelativeDescription: String? {
        guard let viewedAt else {
            return nil
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: viewedAt, relativeTo: .now)
    }

    var recentDistinctKey: String {
        switch contentKind {
        case .track:
            return "track:\(parentTitle ?? ratingKey ?? key ?? title)"
        default:
            return "\(contentKind.rawValue):\(ratingKey ?? key ?? title)"
        }
    }

    var groupedWatchKey: String {
        guard let viewedAt else {
            return "history:\(id)"
        }

        let dayBucket = Int(Calendar.current.startOfDay(for: viewedAt).timeIntervalSince1970)
        let accountBucket = accountID.map(String.init) ?? "account:none"
        let deviceBucket = deviceID.map(String.init) ?? "device:none"
        return "\(recentDistinctKey)|\(accountBucket)|\(deviceBucket)|day:\(dayBucket)"
    }

    func chartGroupKey(seriesByEpisodeID: [String: PlexHistorySeriesIdentity]) -> String? {
        switch contentKind {
        case .tv:
            guard let episodeID = ratingKey?.nilIfBlank,
                  let seriesIdentity = seriesByEpisodeID[episodeID] else {
                return nil
            }

            return "tv:\(seriesIdentity.id)"
        default:
            return "\(contentKind.rawValue):\(ratingKey ?? key ?? title)"
        }
    }

    func chartDisplayTitle(seriesByEpisodeID: [String: PlexHistorySeriesIdentity]) -> String {
        switch contentKind {
        case .tv:
            let episodeID = ratingKey?.nilIfBlank
            return episodeID.flatMap { seriesByEpisodeID[$0]?.title } ?? grandparentTitle ?? title
        default:
            return title
        }
    }

    func chartPosterPath(seriesByEpisodeID: [String: PlexHistorySeriesIdentity]) -> String? {
        switch contentKind {
        case .tv:
            let episodeID = ratingKey?.nilIfBlank
            return episodeID.flatMap { seriesByEpisodeID[$0]?.posterPath } ?? posterPath
        default:
            return posterPath
        }
    }

    func watcherName(using accountsByID: [Int: PlexAccount]) -> String? {
        guard let accountID else {
            return nil
        }

        return accountsByID[accountID]?.name.nilIfBlank
    }

    func watcherAccount(using accountsByID: [Int: PlexAccount]) -> PlexAccount? {
        guard let accountID else {
            return nil
        }

        return accountsByID[accountID]
    }

    private var releaseYear: String? {
        guard let component = originallyAvailableAt?
            .split(separator: "-")
            .first else {
            return nil
        }

        return String(component).nilIfBlank
    }

    private var episodeCode: String? {
        let season = parentIndex.map { "S\($0)" }
        let episode = index.map { String(format: "E%02d", $0) }
        let code = [season, episode].compactMap { $0 }.joined()
        return code.isEmpty ? nil : code
    }

    private var preferredPosterCandidates: [String?] {
        switch contentKind {
        case .tv:
            [grandparentThumb, parentThumb, thumb, art]
        case .track:
            [parentThumb, grandparentThumb, thumb, art]
        default:
            [thumb, parentThumb, grandparentThumb, art]
        }
    }
}

struct PlexTopChartEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let playCount: Int
    let posterPath: String?
    let symbolName: String?
    let watcherSummary: String?
    let watcherAccountIDs: [Int]
    let coverageLabel: String?
    let viewerCountLabel: String?
}

struct PlexUserActivityEntry: Identifiable, Equatable {
    let accountID: Int
    let name: String
    let thumb: String?
    let playCount: Int
    let moviePlayCount: Int
    let tvPlayCount: Int
    let musicPlayCount: Int
    let lastPlayedTitle: String?
    let lastViewedAt: Date?

    var id: Int { accountID }
}

enum PlexHistoryContentFilter: String, CaseIterable, Identifiable {
    case all
    case movies
    case tv

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            "All"
        case .movies:
            "Movies"
        case .tv:
            "TV"
        }
    }

    func includes(_ item: PlexHistoryItem) -> Bool {
        switch self {
        case .all:
            true
        case .movies:
            item.contentKind == .movie
        case .tv:
            item.contentKind == .tv
        }
    }

    var emptyStateMessage: String {
        switch self {
        case .all:
            "No plays found for this history window."
        case .movies:
            "No movie plays in the last 30 days."
        case .tv:
            "No TV plays in the last 30 days."
        }
    }
}

enum PlexHistoryAnalytics {
    static func groupedWatchItems(from items: [PlexHistoryItem]) -> [PlexHistoryItem] {
        Dictionary(grouping: items, by: \.groupedWatchKey)
            .values
            .compactMap(mostRecentItem)
            .sorted(by: isMoreRecent)
    }

    static func recentItems(
        from items: [PlexHistoryItem],
        filter: PlexHistoryContentFilter = .all,
        limit: Int
    ) -> [PlexHistoryItem] {
        Dictionary(grouping: items.lazy.filter(filter.includes), by: \.recentDistinctKey)
            .values
            .compactMap(mostRecentItem)
            .sorted(by: isMoreRecent)
            .prefix(limit)
            .map { $0 }
    }

    static func topTitleEntries(
        from items: [PlexHistoryItem],
        accountsByID: [Int: PlexAccount],
        seriesByEpisodeID: [String: PlexHistorySeriesIdentity],
        limit: Int,
        filter: PlexHistoryContentFilter = .all
    ) -> [PlexTopChartEntry] {
        Dictionary(grouping: items.lazy.filter(filter.includes).compactMap { item in
            item.chartGroupKey(seriesByEpisodeID: seriesByEpisodeID).map { ($0, item) }
        }, by: \.0)
            .values
            .map { $0.map(\.1) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }

                let lhsTitle = lhs.first?.chartDisplayTitle(seriesByEpisodeID: seriesByEpisodeID) ?? ""
                let rhsTitle = rhs.first?.chartDisplayTitle(seriesByEpisodeID: seriesByEpisodeID) ?? ""

                if lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) != .orderedSame {
                    return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
                }

                let lhsID = lhs.first?.chartGroupKey(seriesByEpisodeID: seriesByEpisodeID) ?? ""
                let rhsID = rhs.first?.chartGroupKey(seriesByEpisodeID: seriesByEpisodeID) ?? ""
                return lhsID < rhsID
            }
            .prefix(limit)
            .map { group in
                let representative = group[0]
                let playCount = group.count

                return PlexTopChartEntry(
                    id: representative.chartGroupKey(seriesByEpisodeID: seriesByEpisodeID) ?? representative.id,
                    title: representative.chartDisplayTitle(seriesByEpisodeID: seriesByEpisodeID),
                    subtitle: chartSubtitle(for: group, representative: representative),
                    playCount: playCount,
                    posterPath: representative.chartPosterPath(seriesByEpisodeID: seriesByEpisodeID),
                    symbolName: representative.contentKind.symbolName,
                    watcherSummary: watcherSummary(for: group, accountsByID: accountsByID),
                    watcherAccountIDs: watcherAccountIDs(for: group, accountsByID: accountsByID),
                    coverageLabel: coverageLabel(for: group, representative: representative),
                    viewerCountLabel: viewerCountLabel(for: group)
                )
            }
    }

    static func topTypeEntries(
        from items: [PlexHistoryItem],
        accountsByID: [Int: PlexAccount],
        limit: Int
    ) -> [PlexTopChartEntry] {
        Dictionary(grouping: items, by: \.contentKind)
            .map { kind, group in
                PlexTopChartEntry(
                    id: kind.rawValue,
                    title: kind.displayName,
                    subtitle: group.count == 1 ? "1 recent play" : "\(group.count) recent plays",
                    playCount: group.count,
                    posterPath: nil,
                    symbolName: kind.symbolName,
                    watcherSummary: watcherSummary(for: group, accountsByID: accountsByID),
                    watcherAccountIDs: watcherAccountIDs(for: group, accountsByID: accountsByID),
                    coverageLabel: nil,
                    viewerCountLabel: viewerCountLabel(for: group)
                )
            }
            .sorted {
                if $0.playCount != $1.playCount {
                    return $0.playCount > $1.playCount
                }

                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    static func topUserEntries(
        from items: [PlexHistoryItem],
        accountsByID: [Int: PlexAccount],
        limit: Int
    ) -> [PlexUserActivityEntry] {
        rankedUsers(from: items, accountsByID: accountsByID)
            .prefix(limit)
            .map { $0 }
    }

    static func recentViewerEntries(
        from items: [PlexHistoryItem],
        accountsByID: [Int: PlexAccount],
        limit: Int
    ) -> [PlexUserActivityEntry] {
        rankedUsers(from: items, accountsByID: accountsByID)
            .sorted { lhs, rhs in
                let lhsViewedAt = lhs.lastViewedAt ?? .distantPast
                let rhsViewedAt = rhs.lastViewedAt ?? .distantPast
                if lhsViewedAt != rhsViewedAt {
                    return lhsViewedAt > rhsViewedAt
                }

                if lhs.playCount != rhs.playCount {
                    return lhs.playCount > rhs.playCount
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func chartSubtitle(
        for items: [PlexHistoryItem],
        representative: PlexHistoryItem
    ) -> String {
        switch representative.contentKind {
        case .tv:
            let uniqueEpisodeCount = Set(
                items.map { item in
                    item.ratingKey ?? item.key ?? "\(item.parentIndex ?? -1)-\(item.index ?? -1)-\(item.title)"
                }
            ).count

            if uniqueEpisodeCount <= 1 {
                return items.count == 1 ? "1 recent play" : "\(items.count) recent plays"
            }

            let episodeLabel = uniqueEpisodeCount == 1 ? "episode" : "episodes"
            return "\(items.count) recent plays across \(uniqueEpisodeCount) \(episodeLabel)"
        default:
            return representative.detailLine ?? representative.contentKind.displayName
        }
    }

    private static func coverageLabel(
        for items: [PlexHistoryItem],
        representative: PlexHistoryItem
    ) -> String? {
        switch representative.contentKind {
        case .tv:
            let uniqueEpisodeCount = Set(
                items.map { item in
                    item.ratingKey ?? item.key ?? "\(item.parentIndex ?? -1)-\(item.index ?? -1)-\(item.title)"
                }
            ).count
            let label = uniqueEpisodeCount == 1 ? "episode" : "episodes"
            return "\(uniqueEpisodeCount) \(label)"
        default:
            return nil
        }
    }

    private static func viewerCountLabel(for items: [PlexHistoryItem]) -> String? {
        let uniqueWatcherCount = Set(items.compactMap(\.accountID)).count
        guard uniqueWatcherCount > 0 else {
            return nil
        }

        let label = uniqueWatcherCount == 1 ? "viewer" : "viewers"
        return "\(uniqueWatcherCount) \(label)"
    }

    private static func watcherSummary(
        for items: [PlexHistoryItem],
        accountsByID: [Int: PlexAccount]
    ) -> String? {
        let rankedWatchers = rankedWatchers(for: items, accountsByID: accountsByID)
            .prefix(3)
            .map(\.name)

        guard !rankedWatchers.isEmpty else {
            return nil
        }

        return rankedWatchers.joined(separator: ", ")
    }

    private static func watcherAccountIDs(
        for items: [PlexHistoryItem],
        accountsByID: [Int: PlexAccount]
    ) -> [Int] {
        rankedWatchers(for: items, accountsByID: accountsByID)
            .prefix(3)
            .map(\.id)
    }

    private static func rankedWatchers(
        for items: [PlexHistoryItem],
        accountsByID: [Int: PlexAccount]
    ) -> [(id: Int, name: String, playCount: Int)] {
        Dictionary(grouping: items.compactMap(\.accountID), by: { $0 })
            .map { accountID, plays in
                (
                    id: accountID,
                    name: accountsByID[accountID]?.name ?? "Account \(accountID)",
                    playCount: plays.count
                )
            }
            .sorted {
                if $0.playCount != $1.playCount {
                    return $0.playCount > $1.playCount
                }

                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private static func rankedUsers(
        from items: [PlexHistoryItem],
        accountsByID: [Int: PlexAccount]
    ) -> [PlexUserActivityEntry] {
        Dictionary(grouping: items.compactMap { item in
            item.accountID.map { ($0, item) }
        }, by: \.0)
        .map { accountID, groupedItems in
            let items = groupedItems.map(\.1)
            let account = accountsByID[accountID]
            let mostRecentItem = mostRecentItem(in: items)

            return PlexUserActivityEntry(
                accountID: accountID,
                name: account?.name ?? "Account \(accountID)",
                thumb: account?.thumb,
                playCount: items.count,
                moviePlayCount: items.filter { $0.contentKind == .movie }.count,
                tvPlayCount: items.filter { $0.contentKind == .tv || $0.contentKind == .liveTV }.count,
                musicPlayCount: items.filter { $0.contentKind == .track }.count,
                lastPlayedTitle: mostRecentItem?.headline,
                lastViewedAt: mostRecentItem?.viewedAt
            )
        }
        .sorted {
            if $0.playCount != $1.playCount {
                return $0.playCount > $1.playCount
            }

            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func mostRecentItem(in items: some Sequence<PlexHistoryItem>) -> PlexHistoryItem? {
        items.max(by: { lhs, rhs in
            if let lhsViewedAt = lhs.viewedAt, let rhsViewedAt = rhs.viewedAt, lhsViewedAt != rhsViewedAt {
                return lhsViewedAt < rhsViewedAt
            }

            return lhs.id.localizedCompare(rhs.id) == .orderedAscending
        })
    }

    private static func isMoreRecent(_ lhs: PlexHistoryItem, _ rhs: PlexHistoryItem) -> Bool {
        if let lhsViewedAt = lhs.viewedAt, let rhsViewedAt = rhs.viewedAt, lhsViewedAt != rhsViewedAt {
            return lhsViewedAt > rhsViewedAt
        }

        return lhs.id.localizedCompare(rhs.id) == .orderedDescending
    }
}
