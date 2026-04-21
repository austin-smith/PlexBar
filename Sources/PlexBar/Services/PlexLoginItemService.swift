import ServiceManagement

enum PlexLoginItemStatus: Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
}

@MainActor
protocol PlexLoginItemControlling {
    func status() -> PlexLoginItemStatus
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettingsLoginItems()
}

@MainActor
protocol PlexAppServiceControlling {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: PlexAppServiceControlling {}

struct PlexLoginItemService: PlexLoginItemControlling {
    private let appService: any PlexAppServiceControlling
    private let openSystemSettings: @MainActor () -> Void

    init(
        appService: any PlexAppServiceControlling = SMAppService.mainApp,
        openSystemSettings: @escaping @MainActor () -> Void = { SMAppService.openSystemSettingsLoginItems() }
    ) {
        self.appService = appService
        self.openSystemSettings = openSystemSettings
    }

    func status() -> PlexLoginItemStatus {
        switch appService.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        switch (enabled, appService.status) {
        case (true, .enabled), (true, .requiresApproval), (false, .notRegistered):
            return
        case (true, _):
            try appService.register()
        case (false, _):
            try appService.unregister()
        }
    }

    func openSystemSettingsLoginItems() {
        openSystemSettings()
    }
}
