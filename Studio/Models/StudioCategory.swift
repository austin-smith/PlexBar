import Foundation

enum StudioCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All Content", movies = "Movies", television = "TV Shows", audiobooks = "Audiobooks", users = "Users"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .all: "square.grid.2x2"; case .movies: "film"; case .television: "tv"; case .audiobooks: "book.closed"; case .users: "person.crop.circle" }
    }
}
