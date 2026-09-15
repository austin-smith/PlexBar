import PlexModels
import Foundation

enum PlexMediaSourceURI {
    static func item(
        _ item: PlexMediaItem,
        serverIdentifier: String,
        providerIdentifier: String = PlexMediaProvider.libraryIdentifier
    ) throws -> String {
        guard let serverIdentifier = serverIdentifier.nilIfBlank,
              let itemKey = item.key?.nilIfBlank,
              itemKey.hasPrefix("/") else {
            throw PlexAPIError.missingServerIdentity
        }
        return "server://\(serverIdentifier)/\(providerIdentifier)/\(itemKey.dropFirst())"
    }
}
