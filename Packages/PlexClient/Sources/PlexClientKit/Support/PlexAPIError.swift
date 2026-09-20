import Foundation

public enum PlexAPIError: LocalizedError {
    case invalidServerURL
    case missingToken
    case invalidResponse
    case badStatusCode(Int)
    case decodingFailed(Error)
    case missingHistorySeriesIdentity([String])
    case noPlayableMedia
    case playbackRejected(String)
    case missingServerIdentity
    case invalidPlayQueue
    case invalidDownloadQueue
    case missingLibraryProvider
    case missingLibraryBrowseRoute
    case missingLibraryContinueWatchingFeature
    case missingLibraryPromotedFeature
    case missingLibrarySearchFeature
    case missingLibraryTimelineFeature
    case missingLibraryPlayQueueFeature
    case missingLibraryPlaylistFeature
    case missingLibraryRateFeature
    case missingRemoveFromContinueWatchingAction
    case libraryManagementUnavailable
    case invalidPersonalRating
    case invalidMediaTitle

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid Plex server URL, for example http://192.168.1.10:32400."
        case .missingToken:
            return "Add a Plex token before refreshing sessions."
        case .invalidResponse:
            return "Plex returned a response that PlexBar could not read."
        case .badStatusCode(let statusCode):
            return "Plex returned HTTP \(statusCode). Check the server URL and token."
        case .decodingFailed:
            return "Plex returned data in an unexpected format."
        case .missingHistorySeriesIdentity:
            return "Plex did not return enough metadata to build watch history charts."
        case .noPlayableMedia:
            return "Plex did not return a playable media part."
        case .playbackRejected(let reason):
            return "Plex rejected playback: \(reason)"
        case .missingServerIdentity:
            return "Plex did not provide the selected server identity required to create a play queue."
        case .invalidPlayQueue:
            return "Plex returned a play queue without the selected item."
        case .invalidDownloadQueue:
            return "Plex returned an invalid download queue."
        case .missingLibraryProvider:
            return "Plex did not advertise its library provider."
        case .missingLibraryBrowseRoute:
            return "Plex did not advertise a browse route for this library."
        case .missingLibraryContinueWatchingFeature:
            return "Plex did not advertise the unified Continue Watching feed for its library provider."
        case .missingLibraryPromotedFeature:
            return "Plex did not advertise the Home feed for its library provider."
        case .missingLibrarySearchFeature:
            return "Plex did not advertise search for its library provider."
        case .missingLibraryTimelineFeature:
            return
                "Plex did not advertise the library timeline actions required to update watched status."
        case .missingLibraryPlayQueueFeature:
            return "Plex did not advertise play queues for this library."
        case .missingLibraryPlaylistFeature:
            return "Plex did not advertise playlists for this library."
        case .missingLibraryRateFeature:
            return "Plex did not advertise personal ratings for this library."
        case .missingRemoveFromContinueWatchingAction:
            return "Plex did not advertise removal from Continue Watching."
        case .libraryManagementUnavailable:
            return "This Plex account cannot manage the selected server library."
        case .invalidPersonalRating:
            return "Choose a personal rating from half a star through five stars, or clear the rating."
        case .invalidMediaTitle:
            return "Enter a title."
        }
    }
}
