import PlexClientKit
import Foundation

struct PlexLibraryRequest: Hashable {
    let libraryID: String
    let searchQuery: String
    let browseOptions: PlexLibraryBrowseOptions

    init(
        libraryID: String,
        searchQuery: String,
        browseOptions: PlexLibraryBrowseOptions
    ) {
        self.libraryID = libraryID
        self.searchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.browseOptions = browseOptions
    }

    var isTransient: Bool {
        !searchQuery.isEmpty || browseOptions != .default
    }
}

struct PlexBrowserCacheMetrics: Equatable, Sendable {
    let libraryRequestCount: Int
    let transientLibraryRequestCount: Int
    let libraryItemOccurrenceCount: Int
    let uniqueLibraryItemCount: Int
    let transientRequestCountsByLibraryID: [String: Int]
    let transientRequestLimitPerLibrary: Int
}
