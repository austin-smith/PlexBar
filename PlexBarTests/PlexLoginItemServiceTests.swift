import ServiceManagement
import Testing
@testable import PlexBar

@MainActor
private final class TestAppService: PlexAppServiceControlling {
    var status: SMAppService.Status
    var registerCallCount = 0
    var unregisterCallCount = 0
    var registerError: Error?
    var unregisterError: Error?

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1

        if let registerError {
            throw registerError
        }
    }

    func unregister() throws {
        unregisterCallCount += 1

        if let unregisterError {
            throw unregisterError
        }
    }
}

@MainActor
@Test func enablingPendingApprovalLoginItemDoesNotReRegister() throws {
    let appService = TestAppService(status: .requiresApproval)
    let service = PlexLoginItemService(appService: appService)

    try service.setEnabled(true)

    #expect(appService.registerCallCount == 0)
    #expect(appService.unregisterCallCount == 0)
}
