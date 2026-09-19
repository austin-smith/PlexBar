import PlexClientKit
import PlexModels
import Foundation

enum TVNavigationRoute: Hashable {
    case media(PlexMediaItem)
    case person(PlexPersonRoute)
}
