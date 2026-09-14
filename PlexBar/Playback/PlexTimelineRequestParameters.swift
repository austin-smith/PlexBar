import PlexModels
import Foundation

struct PlexTimelineRequestParameters {
    let update: PlexTimelineUpdate

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "key", value: "/library/metadata/\(update.ratingKey)"),
            URLQueryItem(name: "ratingKey", value: update.ratingKey),
            URLQueryItem(name: "state", value: update.state.rawValue),
            URLQueryItem(name: "time", value: String(max(update.time, 0))),
            URLQueryItem(name: "duration", value: String(max(update.duration, 0)))
        ]
        if let playQueueItemID = update.playQueueItemID?.nilIfBlank {
            items.append(URLQueryItem(name: "playQueueItemID", value: playQueueItemID))
        }
        if update.state == .stopped, let continuing = update.continuing {
            items.append(URLQueryItem(name: "continuing", value: continuing ? "1" : "0"))
        }
        if update.offline {
            items.append(URLQueryItem(name: "offline", value: "1"))
        }
        return items
    }
}

struct PlexWatchedStateRequestParameters {
    let endpointPath: String
    let queryItems: [URLQueryItem]

    init(
        watched: Bool,
        ratingKey: String,
        endpoints: PlexLibraryProviderEndpoints
    ) throws {
        let endpointPath = watched ? endpoints.scrobblePath : endpoints.unscrobblePath
        guard let endpointPath else {
            throw PlexAPIError.missingLibraryTimelineFeature
        }
        self.endpointPath = endpointPath
        queryItems = [
            URLQueryItem(name: "identifier", value: endpoints.providerIdentifier),
            URLQueryItem(name: "key", value: ratingKey),
        ]
    }
}
