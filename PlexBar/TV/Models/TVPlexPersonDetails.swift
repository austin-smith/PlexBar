import PlexModels
import Foundation

struct TVPlexPersonDetails: Sendable {
    let person: PlexTag
    let media: [PlexMediaItem]
}
