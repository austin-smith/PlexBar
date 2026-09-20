import Foundation

enum PlexConnectionStoreError: LocalizedError {
    case noSelectedServer
    case unavailableServerSelection

    var errorDescription: String? {
        switch self {
        case .noSelectedServer:
            return "Select a Plex Media Server in Settings."
        case .unavailableServerSelection:
            return "PlexBar is still loading your server details."
        }
    }
}

extension Error {
    var isPlexConnectivityFailure: Bool {
        plexConnectivityFailureCode != nil
    }

    var plexConnectivityFailureCode: URLError.Code? {
        let urlError = (self as? URLError) ?? (self as NSError).userInfo[NSUnderlyingErrorKey] as? URLError
        guard let urlError else {
            return nil
        }

        switch urlError.code {
        case .badURL,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .resourceUnavailable,
             .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .cannotLoadFromNetwork,
             .cannotCreateFile,
             .cannotOpenFile,
             .cannotCloseFile,
             .cannotWriteToFile,
             .timedOut:
            return urlError.code
        default:
            return nil
        }
    }
}
