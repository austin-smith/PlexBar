import PlexModels
import Foundation

public enum PlexLibrarySortDirection: String, Equatable, Hashable, Sendable {
    case ascending = "asc"
    case descending = "desc"

    public var title: String {
        switch self {
        case .ascending:
            "Ascending"
        case .descending:
            "Descending"
        }
    }
}

public enum PlexLibraryFilterValueType: Equatable, Hashable, Sendable {
    case boolean
    case integer
    case string
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "boolean":
            self = .boolean
        case "integer":
            self = .integer
        case "string":
            self = .string
        default:
            self = .unknown(rawValue)
        }
    }
}

public struct PlexLibraryFilterDefinition: Decodable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let valueType: PlexLibraryFilterValueType
    public let valuesPath: String?

    private enum CodingKeys: String, CodingKey {
        case id = "filter"
        case title
        case filterType
        case valuesPath = "key"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        valueType = PlexLibraryFilterValueType(
            rawValue: try values.decode(String.self, forKey: .filterType)
        )
        valuesPath = try values.decodeIfPresent(String.self, forKey: .valuesPath)?.nilIfBlank
    }
}

public struct PlexLibraryFilterValue: Equatable, Hashable, Identifiable, Sendable {
    public let filterID: String
    public let queryName: String
    public let queryValue: String
    public let title: String

    public var id: String {
        [filterID, queryName, queryValue].joined(separator: "|")
    }

    public init(filterID: String, queryName: String, queryValue: String, title: String) {
        self.filterID = filterID
        self.queryName = queryName
        self.queryValue = queryValue
        self.title = title
    }
}

public struct PlexLibrarySortDefinition: Decodable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let descendingKey: String?
    public let defaultDirection: PlexLibrarySortDirection
    public let defaultSelectionDirection: PlexLibrarySortDirection?

    private enum CodingKeys: String, CodingKey {
        case id = "key"
        case title
        case descendingKey = "descKey"
        case defaultDirection
        case defaultSelectionDirection = "default"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        descendingKey = try values.decodeIfPresent(String.self, forKey: .descendingKey)?.nilIfBlank
        defaultDirection = try values.decodeIfPresent(
            PlexLibrarySortDirection.self,
            forKey: .defaultDirection
        ) ?? .ascending
        defaultSelectionDirection = try values.decodeIfPresent(
            PlexLibrarySortDirection.self,
            forKey: .defaultSelectionDirection
        )
    }

    public func selection(direction: PlexLibrarySortDirection? = nil) -> PlexLibrarySortSelection? {
        let resolvedDirection = direction ?? defaultDirection
        let queryValue: String
        switch resolvedDirection {
        case .ascending:
            queryValue = id
        case .descending:
            guard let descendingKey else {
                return nil
            }
            queryValue = descendingKey
        }
        return PlexLibrarySortSelection(
            sortID: id,
            direction: resolvedDirection,
            queryValue: queryValue
        )
    }
}

extension PlexLibrarySortDirection: Decodable {}

public struct PlexLibrarySortSelection: Equatable, Hashable, Sendable {
    public let sortID: String
    public let direction: PlexLibrarySortDirection
    public let queryValue: String

    public init(sortID: String, direction: PlexLibrarySortDirection, queryValue: String) {
        self.sortID = sortID
        self.direction = direction
        self.queryValue = queryValue
    }
}

public struct PlexLibraryBrowseOptions: Equatable, Hashable, Sendable {
    public static let `default` = PlexLibraryBrowseOptions()

    public var contentTypePath: String?
    public var sort: PlexLibrarySortSelection?
    public var enabledBooleanFilterIDs: Set<String>
    public var valueFilterSelections: [PlexLibraryFilterValue]

    public init(
        contentTypePath: String? = nil,
        sort: PlexLibrarySortSelection? = nil,
        enabledBooleanFilterIDs: Set<String> = [],
        valueFilterSelections: [PlexLibraryFilterValue] = []
    ) {
        self.contentTypePath = contentTypePath
        self.sort = sort
        self.enabledBooleanFilterIDs = enabledBooleanFilterIDs
        self.valueFilterSelections = valueFilterSelections.sorted(by: Self.selectionOrder)
    }

    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let sort {
            items.append(URLQueryItem(name: "sort", value: sort.queryValue))
        }
        items += enabledBooleanFilterIDs.sorted().map {
            URLQueryItem(name: $0, value: "1")
        }
        let selectionsByQueryName = Dictionary(grouping: valueFilterSelections, by: \.queryName)
        items += selectionsByQueryName.keys.sorted().compactMap { queryName in
            guard let selections = selectionsByQueryName[queryName] else {
                return nil
            }
            let values = Set(selections.map(\.queryValue)).sorted()
            guard !values.isEmpty else {
                return nil
            }
            return URLQueryItem(name: queryName, value: values.joined(separator: ","))
        }
        return items
    }

    public var hasFilters: Bool {
        !enabledBooleanFilterIDs.isEmpty || !valueFilterSelections.isEmpty
    }

    public func valueSelections(for filterID: String) -> [PlexLibraryFilterValue] {
        valueFilterSelections.filter { $0.filterID == filterID }
    }

    public mutating func setValueSelections(
        _ selections: [PlexLibraryFilterValue],
        for filterID: String
    ) {
        valueFilterSelections.removeAll { $0.filterID == filterID }
        valueFilterSelections.append(contentsOf: selections)
        valueFilterSelections.sort(by: Self.selectionOrder)
    }

    private static func selectionOrder(
        _ lhs: PlexLibraryFilterValue,
        _ rhs: PlexLibraryFilterValue
    ) -> Bool {
        if lhs.filterID != rhs.filterID {
            return lhs.filterID < rhs.filterID
        }
        if lhs.queryName != rhs.queryName {
            return lhs.queryName < rhs.queryName
        }
        return lhs.queryValue < rhs.queryValue
    }
}

public struct PlexLibraryBrowseDefinition: Equatable, Sendable {
    public let contentPath: String
    public let filters: [PlexLibraryFilterDefinition]
    public let sorts: [PlexLibrarySortDefinition]
    public var types: [PlexLibraryBrowseType] = []

    public func selecting(_ path: String?) throws -> PlexLibraryBrowseDefinition {
        guard let path else { return self }
        guard let type = types.first(where: { $0.key == path }) else {
            throw PlexAPIError.invalidResponse
        }
        return PlexLibraryBrowseDefinition(
            contentPath: type.key, filters: type.filters, sorts: type.sorts, types: types
        )
    }

    public var booleanFilters: [PlexLibraryFilterDefinition] {
        filters.filter { $0.valueType == .boolean }
    }

    public var valueFilters: [PlexLibraryFilterDefinition] {
        filters.filter {
            ($0.valueType == .string || $0.valueType == .integer)
                && $0.valuesPath != nil
        }
    }

    public init(
        contentPath: String,
        filters: [PlexLibraryFilterDefinition],
        sorts: [PlexLibrarySortDefinition],
        types: [PlexLibraryBrowseType] = []
    ) {
        self.contentPath = contentPath
        self.filters = filters
        self.sorts = sorts
        self.types = types
    }
}

public struct PlexLibraryFilterValuesEnvelope: Decodable, Sendable {
    public let mediaContainer: PlexLibraryFilterValuesContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    public init(mediaContainer: PlexLibraryFilterValuesContainer) {
        self.mediaContainer = mediaContainer
    }
}

public struct PlexLibraryFilterValuesContainer: Decodable, Sendable {
    public let directories: [PlexLibraryFilterValueDirectory]

    private enum CodingKeys: String, CodingKey {
        case directories = "Directory"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        directories = try values.decodeIfPresent(
            [PlexLibraryFilterValueDirectory].self,
            forKey: .directories
        ) ?? []
    }

    public func values(for definition: PlexLibraryFilterDefinition) throws -> [PlexLibraryFilterValue] {
        var seenIDs: Set<String> = []
        return try directories.map { directory in
            let value = try directory.value(for: definition)
            guard seenIDs.insert(value.id).inserted else {
                throw PlexAPIError.invalidResponse
            }
            return value
        }
    }
}

public struct PlexLibraryFilterValueDirectory: Decodable, Sendable {
    public let key: String?
    public let filter: String?
    public let title: String?
    public let tag: String?

    private enum CodingKeys: String, CodingKey {
        case key
        case filter
        case title
        case tag
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = values.decodePlexStringIfPresent(forKey: .key)?.nilIfBlank
        filter = try values.decodeIfPresent(String.self, forKey: .filter)?.nilIfBlank
        title = try values.decodeIfPresent(String.self, forKey: .title)?.nilIfBlank
        tag = try values.decodeIfPresent(String.self, forKey: .tag)?.nilIfBlank
    }

    public func value(for definition: PlexLibraryFilterDefinition) throws -> PlexLibraryFilterValue {
        let queryName: String
        let queryValue: String

        if let filter,
           let separator = filter.firstIndex(of: "=") {
            queryName = String(filter[..<separator])
            queryValue = String(filter[filter.index(after: separator)...])
        } else if let key {
            queryName = definition.id
            queryValue = key
        } else {
            throw PlexAPIError.invalidResponse
        }

        guard let resolvedQueryName = queryName.nilIfBlank,
              let resolvedQueryValue = queryValue.nilIfBlank,
              let resolvedTitle = title ?? tag ?? key ?? resolvedQueryValue.nilIfBlank else {
            throw PlexAPIError.invalidResponse
        }

        return PlexLibraryFilterValue(
            filterID: definition.id,
            queryName: resolvedQueryName,
            queryValue: resolvedQueryValue,
            title: resolvedTitle
        )
    }
}

public struct PlexLibraryBrowseEnvelope: Decodable, Sendable {
    public let mediaContainer: PlexLibraryBrowseContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    public init(mediaContainer: PlexLibraryBrowseContainer) {
        self.mediaContainer = mediaContainer
    }
}

public struct PlexLibraryBrowseType: Decodable, Equatable, Identifiable, Sendable {
    public let key: String
    public let type: String
    public let title: String
    public let filters: [PlexLibraryFilterDefinition]
    public let sorts: [PlexLibrarySortDefinition]

    public var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, type, title
        case filters = "Filter"
        case sorts = "Sort"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decode(String.self, forKey: .key)
        type = try values.decode(String.self, forKey: .type)
        title = try values.decode(String.self, forKey: .title)
        // Plex omits Filter for browse types without filters, such as seasons.
        filters = try values.decodeIfPresent([PlexLibraryFilterDefinition].self, forKey: .filters) ?? []
        sorts = try values.decode([PlexLibrarySortDefinition].self, forKey: .sorts)
    }
}

public struct PlexLibraryBrowseContainer: Decodable, Sendable {
    public let directories: [PlexLibraryBrowseDirectory]
    public let types: [PlexLibraryBrowseType]

    private enum CodingKeys: String, CodingKey {
        case directories = "Directory"
        case types = "Type"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        types = try values.decodeIfPresent([PlexLibraryBrowseType].self, forKey: .types) ?? []
        directories = try values.decodeIfPresent(
            [PlexLibraryBrowseDirectory].self,
            forKey: .directories
        ) ?? []
    }
}

public struct PlexLibraryFilterEnvelope: Decodable, Sendable {
    public let mediaContainer: PlexLibraryFilterContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    public init(mediaContainer: PlexLibraryFilterContainer) {
        self.mediaContainer = mediaContainer
    }
}

public struct PlexLibraryFilterContainer: Decodable, Sendable {
    public let filters: [PlexLibraryFilterDefinition]

    private enum CodingKeys: String, CodingKey {
        case filters = "Directory"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        filters = try values.decodeIfPresent(
            [PlexLibraryFilterDefinition].self,
            forKey: .filters
        ) ?? []
    }
}

public struct PlexLibrarySortEnvelope: Decodable, Sendable {
    public let mediaContainer: PlexLibrarySortContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    public init(mediaContainer: PlexLibrarySortContainer) {
        self.mediaContainer = mediaContainer
    }
}

public struct PlexLibrarySortContainer: Decodable, Sendable {
    public let sorts: [PlexLibrarySortDefinition]

    private enum CodingKeys: String, CodingKey {
        case sorts = "Directory"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sorts = try values.decodeIfPresent(
            [PlexLibrarySortDefinition].self,
            forKey: .sorts
        ) ?? []
    }
}

public struct PlexLibraryBrowseDirectory: Decodable, Sendable {
    public let key: String?
    public let metadataTypeID: Int?
    public let filters: [PlexLibraryFilterDefinition]
    public let sorts: [PlexLibrarySortDefinition]

    private enum CodingKeys: String, CodingKey {
        case key
        case metadataTypeID = "type"
        case filters = "Filter"
        case sorts = "Sort"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decodeIfPresent(String.self, forKey: .key)?.nilIfBlank
        if let integer = try? values.decodeIfPresent(Int.self, forKey: .metadataTypeID) {
            metadataTypeID = integer
        } else if let string = try? values.decodeIfPresent(String.self, forKey: .metadataTypeID) {
            metadataTypeID = Int(string)
        } else {
            metadataTypeID = nil
        }
        filters = try values.decodeIfPresent(
            [PlexLibraryFilterDefinition].self,
            forKey: .filters
        ) ?? []
        sorts = try values.decodeIfPresent(
            [PlexLibrarySortDefinition].self,
            forKey: .sorts
        ) ?? []
    }
}

extension PlexLibraryType {
    public var metadataTypeID: Int? {
        switch self {
        case .movie:
            1
        case .show:
            2
        case .artist:
            8
        case .album:
            9
        case .clip:
            12
        case .photo:
            14
        case .photoAlbum:
            14
        case .unknown:
            nil
        }
    }
}
