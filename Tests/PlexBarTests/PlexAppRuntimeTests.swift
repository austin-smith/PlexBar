import Testing
@testable import PlexBar

@MainActor
@Test func defaultsToLiveRuntimeMode() {
    #expect(PlexAppRuntime.mode(arguments: ["PlexBar"]) == .live)
}

#if DEBUG
@MainActor
@Test func selectsMockRuntimeModeFromArgument() {
    #expect(PlexAppRuntime.mode(arguments: ["PlexBar", "--mock"]) == .mock)
}
#endif
