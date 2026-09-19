@testable import PlexClientKit
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PlexModels
import Testing
import UniformTypeIdentifiers
@testable import PlexBar

struct PlexPlaybackPreviewTests {
    @Test func mapsTheSelectedPartAndClampsTheLastFrame() throws {
        let source = try previewSource(parts: #"[{"id":20,"key":"/part/20","duration":2500,"indexes":"sd"}]"#)
        #expect(try source.frame(at: 1.9).offsetMilliseconds == 1_000)
        #expect(try source.frame(at: 2.5).offsetMilliseconds == 2_000)
        #expect(try source.frame(at: 0).partID == 20)
        #expect(throws: PlexPlaybackPreviewError.invalidTimeline) { try source.frame(at: .nan) }
        #expect(throws: PlexPlaybackPreviewError.invalidTimeline) { try source.frame(at: -1) }
        #expect(throws: PlexPlaybackPreviewError.invalidTimeline) { try source.frame(at: .infinity) }
    }

    @Test func multipartBoundariesUsePartLocalMilliseconds() throws {
        let source = try previewSource(parts: #"[{"id":1,"duration":10500,"indexes":"sd"},{"id":2,"duration":2200,"indexes":"sd"}]"#)
        #expect(try source.frame(at: 10.499).partID == 1)
        #expect(try source.frame(at: 10.5).partID == 2)
        #expect(try source.frame(at: 10.5).offsetMilliseconds == 0)
        #expect(try source.frame(at: 11.6).offsetMilliseconds == 1_000)
        #expect(try source.frame(at: 12.7).offsetMilliseconds == 2_000)
        #expect(throws: PlexPlaybackPreviewError.invalidTimeline) { try source.frame(at: 13) }
    }

    @Test func refusesToGuessMissingPartDurationsOrIndexes() throws {
        let missingDuration = try previewSource(parts: #"[{"id":1,"indexes":"sd"},{"id":2,"duration":2200,"indexes":"sd"}]"#)
        #expect(throws: PlexPlaybackPreviewError.invalidTimeline) { try missingDuration.frame(at: 2) }
        let noIndex = try previewSource(parts: #"[{"id":1,"duration":2000}]"#)
        #expect(throws: PlexPlaybackPreviewError.noIndex) { try noIndex.frame(at: 0) }
    }

    @Test func trackCoordinatesMatchPreviewAndSeekAtBothEnds() {
        let track = PlexPlayerTimelineGeometry(width: 410, duration: 7_200)
        #expect(track.time(at: 5) == 0)
        #expect(track.time(at: 405) == 7_200)
        #expect(track.time(at: 205) == 3_600)
        #expect(track.time(at: -100) == 0)
        #expect(track.time(at: 800) == 7_200)
        #expect(track.x(for: 3_600) + PlexPlayerTimelineGeometry.inset == 205)
        #expect(PlexPlayerTimelineGeometry(width: 0, duration: 20).time(at: 1) == 0)
    }
}

@MainActor
struct PlexPlaybackPreviewStoreTests {
    @Test func escapeDuringScrubbingCancelsWithoutRequiringTimelineFocus() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        ))
        #expect(PlexPlayerTransportKeyboardHandler.action(
            for: event, hasFocusedControl: false, isFullScreenActive: true, isScrubbing: true
        ) == .cancelScrub)
    }

    @Test func coalescesPointerMovementAndRejectsStaleImages() async throws {
        let loader = PreviewControlledLoader()
        let source = try previewSource()
        let store = PlexPlaybackPreviewStore(interval: .zero, load: loader.load)
        store.show(at: 1, source: .server(source))
        try await previewEventually { await loader.count == 1 }
        store.show(at: 2, source: .server(source))
        store.show(at: 3, source: .server(source))
        #expect(await loader.count == 1)
        await loader.finish(0, result: .success(try previewImage()))
        try await previewEventually { await loader.count == 2 }
        #expect(store.image == nil)
        #expect(await loader.offsets == [1_000, 3_000])
        await loader.finish(1, result: .success(try previewImage()))
        try await previewEventually { store.image != nil }
        #expect(store.position == 3)
        store.show(at: 1.8, source: .server(source))
        #expect(store.image != nil)
        #expect(!store.isLoading)
        #expect(await loader.count == 2)
        store.hide()
    }

    @Test func exitCancelsRequestsAndOldCompletionCannotReplaceNewSession() async throws {
        let loader = PreviewControlledLoader()
        let store = PlexPlaybackPreviewStore(interval: .zero, load: loader.load)
        store.show(at: 1, source: .server(try previewSource()))
        try await previewEventually { await loader.count == 1 }
        store.hide()
        #expect(store.position == nil)
        store.show(at: 1, source: .server(try previewSource(sessionID: "second")))
        try await previewEventually { await loader.count == 2 }
        await loader.finish(0, result: .success(try previewImage()))
        await loader.finish(1, result: .success(try previewImage(width: 4)))
        try await previewEventually { store.image != nil }
        #expect(store.image?.image.width == 4)
        #expect(await loader.cancelled == [true, false])
        store.hide()
    }

    @Test func knownMissingIndexStopsFurtherRequestsForThePart() async throws {
        let loader = PreviewControlledLoader()
        let source = try previewSource()
        let store = PlexPlaybackPreviewStore(interval: .zero, load: loader.load)
        store.show(at: 1, source: .server(source))
        try await previewEventually { await loader.count == 1 }
        store.show(at: 2, source: .server(source))
        await loader.finish(0, result: .failure(PlexPlaybackPreviewError.noIndex))
        try await previewEventually { !store.isLoading }
        store.show(at: 10, source: .server(source))
        #expect(store.message == PlexPlaybackPreviewError.noIndex.localizedDescription)
        #expect(await loader.count == 1)
        store.hide()
        store.show(at: 20, source: .server(source))
        #expect(await loader.count == 1)
        store.hide()
    }

    @Test func cacheSurvivesPointerExitButNotAnAccountOrSourceChange() async throws {
        let loader = PreviewControlledLoader()
        let source = try previewSource()
        let store = PlexPlaybackPreviewStore(interval: .zero, load: loader.load)
        store.show(at: 1, source: .server(source))
        try await previewEventually { await loader.count == 1 }
        await loader.finish(0, result: .success(try previewImage()))
        try await previewEventually { store.image != nil }
        store.hide()
        store.show(at: 1, source: .server(source))
        #expect(store.image != nil)
        #expect(await loader.count == 1)
        store.show(at: 1, source: .server(try previewSource(token: "other-account")))
        #expect(store.image == nil)
        try await previewEventually { await loader.count == 2 }
        await loader.finish(1, result: .success(try previewImage()))
        try await previewEventually { store.image != nil }
        store.hide()
    }
}

private actor PreviewControlledLoader {
    var frames: [PlexPlaybackPreviewFrame] = []
    var pending: [Int: CheckedContinuation<PlexCGImageBox, Error>] = [:]
    var cancelled: [Bool] = []
    var count: Int { frames.count }
    var offsets: [Int] { frames.map(\.offsetMilliseconds) }

    func load(_ frame: PlexPlaybackPreviewFrame, source: PlexServerPlaybackPreviewSource) async throws -> PlexCGImageBox {
        let index = frames.count
        frames.append(frame)
        let image = try await withCheckedThrowingContinuation { pending[index] = $0 }
        cancelled.append(Task.isCancelled)
        return image
    }

    func finish(_ index: Int, result: Result<PlexCGImageBox, Error>) {
        pending.removeValue(forKey: index)?.resume(with: result)
    }
}

func previewSource(
    parts: String = #"[{"id":20,"key":"/part/20","duration":60000,"indexes":"sd"}]"#,
    sessionID: String = "first",
    token: String = "fixture-token"
) throws -> PlexServerPlaybackPreviewSource {
    PlexServerPlaybackPreviewSource(
        serverURL: URL(string: "https://plex.example.test:32400")!,
        token: token,
        clientContext: PlexClientContext(clientIdentifier: "preview-tests"),
        sessionIdentifier: sessionID,
        parts: try JSONDecoder().decode([PlexMediaPart].self, from: Data(parts.utf8))
    )
}

func previewImage(width: Int = 2) throws -> PlexCGImageBox {
    let context = try #require(CGContext(data: nil, width: width, height: 2, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    return PlexCGImageBox(try #require(context.makeImage()))
}

@MainActor
func previewEventually(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
    try #require(await condition())
}
