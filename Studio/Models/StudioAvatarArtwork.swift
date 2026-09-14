import Foundation
import PlexMockData

/// Keeps avatar destinations stable and their labels independent of storage filenames.
enum StudioAvatarArtwork {
    static func path(for user: PlexMockServerPayload.User, in pack: StudioPack) throws -> String {
        if let avatar = user.avatar {
            guard pack.assets.contains(where: { $0.path == avatar && $0.role == .avatar }) else {
                throw StudioError.invalid("This user’s avatar is not registered as avatar artwork.")
            }
            return avatar
        }
        let username = user.username.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                             locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        let filename = username.split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
        guard !filename.isEmpty else {
            throw StudioError.invalid("The username does not produce a valid avatar filename.")
        }
        let resource = "avatars/\(filename).png"
        let path = "/mock/\(resource)"
        guard !pack.assets.contains(where: { $0.path == path || $0.resource == resource }) else {
            throw StudioError.invalid("The avatar filename \(filename).png is already in use. Select that avatar or choose a different username.")
        }
        return path
    }

    struct Choice: Identifiable {
        let path: String
        let title: String
        var id: String { path }
    }

    static func choices(in pack: StudioPack) throws -> [Choice] {
        guard let values = pack.payload["users"] else { throw StudioError.invalid("Mock users are missing.") }
        let users = try JSONDecoder().decode([PlexMockServerPayload.User].self, from: values.encoded())
        return pack.assets.filter { $0.role == .avatar }.map { asset in
            let names = users.filter { $0.avatar == asset.path }.map(\.name)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let title = names.isEmpty
                ? URL(fileURLWithPath: asset.resource).deletingPathExtension().lastPathComponent
                : names.joined(separator: ", ")
            return Choice(path: asset.path, title: title)
        }.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }
}
