import PlexMockData

/// Captures the profile and signed-in selection together when its editor opens.
struct StudioUserEdit: Identifiable {
    let user: PlexMockServerPayload.User
    let authenticatedUserID: Int
    var id: Int { user.id }
}
