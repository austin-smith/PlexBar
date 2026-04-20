import Foundation

struct PlexAuthenticatedUser: Decodable, Equatable, Identifiable {
    let id: Int
    let username: String
    let title: String?
    let email: String?
    let thumb: String?
    let friendlyName: String?

    var displayName: String {
        title?.nilIfBlank ?? username
    }

    var displayEmail: String? {
        email?.nilIfBlank
    }

    var displayUsername: String? {
        let normalizedUsername = username.nilIfBlank
        guard let normalizedUsername,
              normalizedUsername != displayName else {
            return nil
        }

        return normalizedUsername
    }
}
