import PlexModels
import Foundation

enum PlexLibrarySortDirection: String, Equatable, Hashable, Sendable {
    case ascending = "asc"
    case descending = "desc"

    var title: String {
        switch self {
        case .ascending:
            "Ascending"
        case .descending:
            "Descending"
        }
    }
}

enum PlexLibraryFilterValueType: Equatable, Hashable, Sendable {
    case boolean
    case integer
    case string
    case unknown(String)

    init(rawValue: String) {
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

struct PlexLibraryFilterDefinition: Decodable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let valueType: PlexLibraryFilterValueType
    let valuesPath: String?

    private enum CodingKeys: String, CodingKey {
        case id = "filter"
        case title
        case filterType
        case valuesPath = "key"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        valueType = PlexLibraryFilterValueType(
            rawValue: try values.decode(String.self, forKey: .filterType)
        )
        valuesPath = try values.decodeIfPresent(String.self, forKey: .valuesPath)?.nilIfBlank
    }
}

struct PlexLibraryFilterValue: Equatable, Hashable, Identifiable, Sendable {
    let filterID: String
    let queryName: String
    let queryValue: String
    let title: String

    var id: String {
        [filterID, queryName, queryValue].joined(separator: "|")
    }
}

struct PlexLibrarySortDefinition: Decodable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let descendingKey: String?
    let defaultDirection: PlexLibrarySortDirection
    let defaultSelectionDirection: PlexLibrarySortDirection?

    private enum CodingKeys: String, CodingKey {
        case id = "key"
        case title
        case descendingKey = "descKey"
        case defaultDirection
        case defaultSelectionDirection = "default"
    }

    init(from decoder: Decoder) throws {
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

    func selection(direction: PlexLibrarySortDirection? = nil) -> PlexLibrarySortSelection? {
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

struct PlexLibrarySortSelection: Equatable, Hashable, Sendable {
    let sortID: String
    let direction: PlexLibrarySortDirection
    let queryValue: String
}

struct PlexLibraryBrowseOptions: Equatable, Hashable, Sendable {
    static let `default` = PlexLibraryBrowseOptions()

    var contentTypePath: String?
    var sort: PlexLibrarySortSelection?
    var enabledBooleanFilterIDs: Set<String>
    var valueFilterSelections: [PlexLibraryFilterValue]

    init(
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

    var queryItems: [URLQueryItem] {
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

    var hasFilters: Bool {
        !enabledBooleanFilterIDs.isEmpty || !valueFilterSelections.isEmpty
    }

    func valueSelections(for filterID: String) -> [PlexLibraryFilterValue] {
        valueFilterSelections.filter { $0.filterID == filterID }
    }

    mutating func setValueSelections(
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

struct PlexLibraryBrowseDefinition: Equatable, Sendable {
    let contentPath: String
    let filters: [PlexLibraryFilterDefinition]
    let sorts: [PlexLibrarySortDefinition]
    var types: [PlexLibraryBrowseType] = []

    func selecting(_ path: String?) throws -> PlexLibraryBrowseDefinition {
        guard let path else { return self }
        guard let type = types.first(where: { $0.key == path }) else {
            throw PlexAPIError.invalidResponse
        }
        return PlexLibraryBrowseDefinition(
            contentPath: type.key, filters: type.filters, sorts: type.sorts, types: types
        )
    }

    var booleanFilters: [PlexLibraryFilterDefinition] {
        filters.filter { $0.valueType == .boolean }
    }

    var valueFilters: [PlexLibraryFilterDefinition] {
        filters.filter {
            ($0.valueType == .string || $0.valueType == .integer)
                && $0.valuesPath != nil
        }
    }
}

struct PlexLibraryFilterValuesEnvelope: Decodable, Sendable {
    let mediaContainer: PlexLibraryFilterValuesContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexLibraryFilterValuesContainer: Decodable, Sendable {
    let directories: [PlexLibraryFilterValueDirectory]

    private enum CodingKeys: String, CodingKey {
        case directories = "Directory"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        directories = try values.decodeIfPresent(
            [PlexLibraryFilterValueDirectory].self,
            forKey: .directories
        ) ?? []
    }

    func values(for definition: PlexLibraryFilterDefinition) throws -> [PlexLibraryFilterValue] {
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

struct PlexLibraryFilterValueDirectory: Decodable, Sendable {
    let key: String?
    let filter: String?
    let title: String?
    let tag: String?

    private enum CodingKeys: String, CodingKey {
        case key
        case filter
        case title
        case tag
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = values.decodePlexStringIfPresent(forKey: .key)?.nilIfBlank
        filter = try values.decodeIfPresent(String.self, forKey: .filter)?.nilIfBlank
        title = try values.decodeIfPresent(String.self, forKey: .title)?.nilIfBlank
        tag = try values.decodeIfPresent(String.self, forKey: .tag)?.nilIfBlank
    }

    func value(for definition: PlexLibraryFilterDefinition) throws -> PlexLibraryFilterValue {
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

struct PlexLibraryBrowseEnvelope: Decodable, Sendable {
    let mediaContainer: PlexLibraryBrowseContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexLibraryBrowseType: Decodable, Equatable, Identifiable, Sendable {
    let key: String
    let type: String
    let title: String
    let filters: [PlexLibraryFilterDefinition]
    let sorts: [PlexLibrarySortDefinition]

    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, type, title
        case filters = "Filter"
        case sorts = "Sort"
    }
}

struct PlexLibraryBrowseContainer: Decodable, Sendable {
    let directories: [PlexLibraryBrowseDirectory]
    let types: [PlexLibraryBrowseType]

    private enum CodingKeys: String, CodingKey {
        case directories = "Directory"
        case types = "Type"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        types = try values.decodeIfPresent([PlexLibraryBrowseType].self, forKey: .types) ?? []
        directories = try values.decodeIfPresent(
            [PlexLibraryBrowseDirectory].self,
            forKey: .directories
        ) ?? []
    }
}

struct PlexLibraryFilterEnvelope: Decodable, Sendable {
    let mediaContainer: PlexLibraryFilterContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexLibraryFilterContainer: Decodable, Sendable {
    let filters: [PlexLibraryFilterDefinition]

    private enum CodingKeys: String, CodingKey {
        case filters = "Directory"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        filters = try values.decodeIfPresent(
            [PlexLibraryFilterDefinition].self,
            forKey: .filters
        ) ?? []
    }
}

struct PlexLibrarySortEnvelope: Decodable, Sendable {
    let mediaContainer: PlexLibrarySortContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexLibrarySortContainer: Decodable, Sendable {
    let sorts: [PlexLibrarySortDefinition]

    private enum CodingKeys: String, CodingKey {
        case sorts = "Directory"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sorts = try values.decodeIfPresent(
            [PlexLibrarySortDefinition].self,
            forKey: .sorts
        ) ?? []
    }
}

struct PlexLibraryBrowseDirectory: Decodable, Sendable {
    let key: String?
    let metadataTypeID: Int?
    let filters: [PlexLibraryFilterDefinition]
    let sorts: [PlexLibrarySortDefinition]

    private enum CodingKeys: String, CodingKey {
        case key
        case metadataTypeID = "type"
        case filters = "Filter"
        case sorts = "Sort"
    }

    init(from decoder: Decoder) throws {
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
    var metadataTypeID: Int? {
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
