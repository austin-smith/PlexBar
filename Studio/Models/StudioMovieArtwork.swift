import Foundation

enum StudioMovieArtwork {
    /// Movie artwork shares one title folder. An existing folder remains stable after title edits.
    static func path(for record: StudioCatalogRecord, role: StudioArtworkRole, in pack: StudioPack) throws -> String {
        guard record.type == "movie", role == .poster || role == .backdrop else {
            throw StudioError.invalid("Movie artwork must be a poster or backdrop.")
        }
        let existing = pack.artwork(for: record)
        let folders = try Set(existing.map { asset in
            let parts = asset.path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 6, parts[0].isEmpty, parts[1] == "mock", parts[2] == "art",
                  parts[3] == "movies", !parts[4].isEmpty, parts[4] != ".", parts[4] != ".." else {
                throw StudioError.invalid("\(record.title) has artwork outside its movie folder: \(asset.path)")
            }
            return String(parts[4])
        })
        guard folders.count <= 1 else {
            throw StudioError.invalid("\(record.title) has artwork in more than one movie folder.")
        }
        let folder: String
        if let existingFolder = folders.first {
            folder = existingFolder
        } else {
            let title = record.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            folder = title.split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
            guard !folder.isEmpty else { throw StudioError.invalid("The movie title does not produce a valid artwork folder name.") }
        }
        let directory = "/mock/art/movies/\(folder)/"
        let ownedPaths = Set(existing.map(\.path))
        guard !pack.assets.contains(where: { $0.path.hasPrefix(directory) && !ownedPaths.contains($0.path) }),
              !pack.records.contains(where: { other in
                  other.type == "movie" && other.id != record.id && ["thumb", "art"].contains { field in
                      other.metadata[field]?.string?.hasPrefix(directory) == true
                  }
              }) else {
            throw StudioError.invalid("The artwork folder \(directory) is already used by another catalog item.")
        }
        return directory + (role == .poster ? "poster.png" : "backdrop.jpg")
    }
}
