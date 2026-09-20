#if os(tvOS)
import XCTest

/// Runs against the configured Plex server. Keep this in the separate live UI scheme.
@MainActor
final class TVRemoteNavigationTests: XCTestCase {
    func testLibrarySortAndFilterMenusUseServerChoices() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let libraries = app.tabBars.buttons["Libraries"]
        guard libraries.waitForExistence(timeout: 20) else { throw XCTSkip("Requires a signed-in server.") }
        for _ in 0..<5 {
            if libraries.hasFocus { break }
            XCUIRemote.shared.press(.right)
        }
        XCTAssertTrue(libraries.hasFocus)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.down)
        capture(app, name: "Libraries")
        XCUIRemote.shared.press(.select)
        let sort = app.buttons["library-sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        let ready = expectation(for: NSPredicate { _, _ in sort.isEnabled }, evaluatedWith: sort)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        let movies = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'media.movie.'"))
        XCTAssertTrue(movies.firstMatch.waitForExistence(timeout: 15))
        let originalFirstMovie = movies.firstMatch.identifier
        capture(app, name: "Library grid and controls")
        XCUIRemote.shared.press(.down)
        for _ in 0..<6 { XCUIRemote.shared.press(.right) }
        for _ in 0..<5 {
            if containsFocus(sort) { break }
            XCUIRemote.shared.press(.up)
        }
        for _ in 0..<4 {
            if containsFocus(sort) { break }
            XCUIRemote.shared.press(.left)
        }
        capture(app, name: "Library sort focus")
        XCTAssertTrue(containsFocus(sort))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "Server sort choices")
        try selectMenuChoice("Release Date", in: app)
        XCTAssertTrue(app.cells.firstMatch.waitForNonExistence(timeout: 5))
        let sorted = expectation(for: NSPredicate { _, _ in
            movies.firstMatch.exists && movies.firstMatch.identifier != originalFirstMovie
        }, evaluatedWith: app)
        XCTAssertEqual(XCTWaiter.wait(for: [sorted], timeout: 15), .completed)
        XCTAssertEqual(sort.value as? String, "Release Date")
        capture(app, name: "Sorted library")
        let unfilteredFirstMovie = movies.firstMatch.identifier
        XCUIRemote.shared.press(.right)
        let filter = app.buttons["library-filter"]
        XCTAssertTrue(containsFocus(filter))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "Server filter choices")
        try selectMenuChoice("Genre", in: app)
        XCTAssertTrue(app.buttons["Apply"].waitForExistence(timeout: 10))
        capture(app, name: "Genre filter values")
        let actionGenre = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'filter-value.' AND label == 'Action'")).firstMatch
        XCTAssertTrue(actionGenre.waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(containsFocus(app.cells.containing(.button, identifier: actionGenre.identifier).firstMatch))
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(actionGenre.value as? String, "Selected")
        let apply = app.buttons["Apply (1)"]
        for _ in 0..<40 {
            if containsFocus(app.buttons["Clear"]) || containsFocus(app.buttons["Cancel"]) || containsFocus(apply) { break }
            XCUIRemote.shared.press(.down)
        }
        for _ in 0..<3 {
            if containsFocus(apply) { break }
            XCUIRemote.shared.press(.right)
        }
        XCTAssertTrue(containsFocus(apply))
        capture(app, name: "Selected genre ready to apply")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5))
        let filtered = expectation(for: NSPredicate { _, _ in
            movies.firstMatch.exists && movies.firstMatch.identifier != unfilteredFirstMovie
        }, evaluatedWith: app)
        XCTAssertEqual(XCTWaiter.wait(for: [filtered], timeout: 15), .completed)
        capture(app, name: "Filtered library")
        XCUIRemote.shared.press(.menu)
    }

    func testHomeRemoteMovesBetweenMediaWithoutHeadingStops() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'media.'"))
        guard cards.firstMatch.waitForExistence(timeout: 20) else { throw XCTSkip("Requires signed-in Home media.") }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hub-show-all.'")).count, 0)
        XCTAssertFalse(app.buttons["Show All"].exists)
        XCTAssertFalse(app.buttons["Load More"].exists)
        XCTAssertEqual(cards.matching(NSPredicate(format:
            "identifier BEGINSWITH 'media.album.' OR identifier BEGINSWITH 'media.artist.' OR identifier BEGINSWITH 'media.track.'"
        )).count, 0, "Apple TV Home should promote movies and TV, not audio libraries.")
        XCUIRemote.shared.press(.down)
        let first = try XCTUnwrap(cards.allElementsBoundByIndex.first(where: containsFocus))
        XCUIRemote.shared.press(.right)
        let second = try XCTUnwrap(cards.allElementsBoundByIndex.first(where: containsFocus))
        XCTAssertNotEqual(first.identifier, second.identifier)
        XCTAssertEqual(first.frame.midY, second.frame.midY, accuracy: 30)
        capture(app, name: "Horizontal media navigation")
        XCUIRemote.shared.press(.down)
        let nextRow = try XCTUnwrap(cards.allElementsBoundByIndex.first(where: containsFocus),
                                    "Down must reach media in the next shelf, without a header button stop.")
        XCTAssertNotEqual(nextRow.identifier, second.identifier)
        capture(app, name: "Down goes directly to next shelf")
        XCUIRemote.shared.press(.up)
        let returned = try XCTUnwrap(cards.allElementsBoundByIndex.first(where: containsFocus))
        XCTAssertEqual(returned.identifier, second.identifier)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail-play.'")).firstMatch
            .waitForExistence(timeout: 15))
        let originalPlayID = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail-play.'")).firstMatch.identifier
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "Back to the originating shelf")
        // AX can omit the restored focus flag. Select tests the remote's actual target.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons[originalPlayID].waitForExistence(timeout: 10),
                      "Select after Back must reopen the same episode or movie.")
        XCUIRemote.shared.press(.menu)
    }

    private func containsFocus(_ element: XCUIElement) -> Bool {
        element.hasFocus || element.descendants(matching: .any).allElementsBoundByIndex.contains(where: \.hasFocus)
    }

    private func selectMenuChoice(_ title: String, in app: XCUIApplication) throws {
        let choice = app.cells.containing(.any, identifier: title).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        for _ in 0..<30 {
            if containsFocus(choice) { break }
            let focused = try XCTUnwrap(app.cells.allElementsBoundByIndex.first(where: containsFocus))
            XCUIRemote.shared.press(choice.frame.midY < focused.frame.midY ? .up : .down)
        }
        XCTAssertTrue(containsFocus(choice))
        XCUIRemote.shared.press(.select)
    }

    func testHomeDetailAndBackWithNativeRemote() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let cards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'media.'")
        )
        guard cards.firstMatch.waitForExistence(timeout: 20) else {
            capture(app, name: "Home prerequisite")
            throw XCTSkip("Requires a signed-in Plex server with media on Home.")
        }
        capture(app, name: "Home")
        XCUIRemote.shared.press(.down)
        let movie = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'media.movie.'")).firstMatch
        guard movie.exists else { throw XCTSkip("Requires a movie in the first Home row.") }
        for _ in 0..<12 {
            if movie.hasFocus { break }
            let current = try XCTUnwrap(app.buttons.allElementsBoundByIndex.first(where: \.hasFocus))
            XCUIRemote.shared.press(movie.frame.midX < current.frame.midX ? .left : .right)
        }
        XCTAssertTrue(movie.hasFocus)
        let focused = try XCTUnwrap(cards.allElementsBoundByIndex.first(where: \.hasFocus), "Down should focus a media card.")
        let cardIdentifier = focused.identifier
        capture(app, name: "Focused Home card")
        XCUIRemote.shared.press(.select)
        let playButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail-play.'")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 15), "Select should open media details with a playback action.")
        XCTAssertTrue(playButton.hasFocus, "Opening details should focus Play or Resume, not the description.")
        let originalPlaybackLabel = playButton.label
        let trailer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Trailer for '")).firstMatch
        if trailer.exists {
            XCTAssertEqual(trailer.staticTexts.count, 0, "Trailer should display only its icon.")
        }
        capture(app, name: "Media detail")
        let summary = app.buttons["detail-summary"]
        if summary.exists {
            XCTAssertFalse(app.buttons["Full Synopsis"].exists, "The description itself replaces the Info action.")
            XCUIRemote.shared.press(.up)
            XCTAssertTrue(summary.hasFocus, "Up from Play should focus the description.")
            capture(app, name: "Focused description")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
            capture(app, name: "Full description")
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(app.buttons["Done"].waitForNonExistence(timeout: 5))
            XCUIRemote.shared.press(.down)
        }
        XCUIRemote.shared.press(.menu)
        let restored = cards.matching(identifier: cardIdentifier).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        capture(app, name: "Restored Home focus")
        // SwiftUI's restored card can be highlighted while AX reports no focused element.
        // Verify the remote's effective target rather than relying on that stale AX flag.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        XCTAssertEqual(playButton.label, originalPlaybackLabel, "Select after Back should reopen the originating title.")
        XCUIRemote.shared.press(.menu)
    }

    func testSeasonSwitchAndEpisodeSelectionStayOnOneDetailPage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let episodeCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'media.episode.'"))
        guard episodeCards.firstMatch.waitForExistence(timeout: 20) else {
            throw XCTSkip("Requires an episode on Home and a series with multiple seasons.")
        }
        let target = episodeCards.firstMatch
        let originIdentifier = target.identifier
        XCUIRemote.shared.press(.down)
        for _ in 0..<12 {
            if target.hasFocus { break }
            let current = try XCTUnwrap(app.buttons.allElementsBoundByIndex.first(where: \.hasFocus))
            XCUIRemote.shared.press(target.frame.midX < current.frame.midX ? .left : .right)
        }
        XCTAssertTrue(target.hasFocus, "The Home episode must be reachable with the remote.")
        XCUIRemote.shared.press(.select)
        let picker = app.buttons["season-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15), "Requires the Home episode's multi-season picker.")
        let oldSeason = picker.value as? String
        let rowCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'media.episode.'"))
        XCTAssertTrue(rowCards.firstMatch.waitForExistence(timeout: 10))
        let oldEpisodeIDs = Set(rowCards.allElementsBoundByIndex.map(\.identifier))
        capture(app, name: "Episode detail")
        XCUIRemote.shared.press(.down)
        capture(app, name: "Down from episode playback")
        XCUIRemote.shared.press(.select)
        capture(app, name: "Open season picker")
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5), "Select should open the native season menu.")
        XCUIRemote.shared.press(.down)
        let nextOption = try XCTUnwrap(app.cells.allElementsBoundByIndex.first(where: \.hasFocus))
        let nextSeason = nextOption.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Season '"))
            .firstMatch.label
        XCTAssertNotEqual(nextSeason, oldSeason)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, nextSeason)
        let episodesChanged = expectation(for: NSPredicate { _, _ in
            let ids = Set(rowCards.allElementsBoundByIndex.map(\.identifier))
            return !ids.isEmpty && ids != oldEpisodeIDs
        }, evaluatedWith: app)
        XCTAssertEqual(XCTWaiter.wait(for: [episodesChanged], timeout: 10), .completed,
                       "Changing seasons must replace the episode row, not just the heading.")
        capture(app, name: "Changed season")
        XCUIRemote.shared.press(.down)
        let selectedEpisode = try XCTUnwrap(rowCards.allElementsBoundByIndex.first(where: { card in
            card.hasFocus || card.descendants(matching: .any).allElementsBoundByIndex.contains(where: \.hasFocus)
        }))
        let ratingKey = try XCTUnwrap(selectedEpisode.identifier.split(separator: ".").last)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["detail-play.\(ratingKey)"].waitForExistence(timeout: 10))
        capture(app, name: "Selected episode in place")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons.matching(identifier: originIdentifier).firstMatch.waitForExistence(timeout: 5), "One Back should return Home after selecting an episode.")
    }

    func testNativePlaybackResumesAdvancesAndDismisses() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'media.'"))
        guard cards.firstMatch.waitForExistence(timeout: 20) else {
            capture(app, name: "Playback Home prerequisite unavailable")
            throw XCTSkip("Requires a signed-in Plex server with playable Home media.")
        }
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.select)
        let play = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail-play.'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        let detailIdentifier = play.identifier
        let resumeTime = play.label.split(separator: " ").compactMap { clockSeconds(String($0)) }.first ?? 0
        capture(app, name: "Before playback")
        XCUIRemote.shared.press(.select)
        let player = app.otherElements["native-player"]
        XCTAssertTrue(player.waitForExistence(timeout: 30), "Playback should present the native AVKit player.")
        let elapsed = player.otherElements["AXElapsedTime"]
        let resumed = expectation(for: NSPredicate { _, _ in
            guard elapsed.exists, let seconds = self.clockSeconds(elapsed.label) else { return false }
            return seconds >= max(1, resumeTime - 15)
        }, evaluatedWith: player)
        let resumeResult = XCTWaiter.wait(for: [resumed], timeout: 45)
        capture(app, name: "Native playback readiness")
        XCTAssertEqual(resumeResult, .completed, "The native playback clock must reach the saved resume position.")
        let initialTime = try XCTUnwrap(clockSeconds(elapsed.label))
        let advancing = expectation(for: NSPredicate { _, _ in
            guard elapsed.exists, let seconds = self.clockSeconds(elapsed.label) else { return false }
            return seconds >= initialTime + 3
        }, evaluatedWith: player)
        let advancingResult = XCTWaiter.wait(for: [advancing], timeout: 15)
        capture(app, name: "Native playback advancing")
        XCTAssertEqual(advancingResult, .completed, "Playback must advance after resuming.")
        XCUIRemote.shared.press(.playPause)
        let pausedTime = try XCTUnwrap(clockSeconds(elapsed.label))
        let remainsPaused = expectation(for: NSPredicate { _, _ in
            guard elapsed.exists, let seconds = self.clockSeconds(elapsed.label) else { return false }
            return seconds > pausedTime + 1
        }, evaluatedWith: player)
        remainsPaused.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [remainsPaused], timeout: 4), .completed,
                       "The native remote's Play Pause command must stop playback progress.")
        XCTAssertFalse(player.cells["Audio & Subtitles"].exists,
                       "Plex-specific adjustments belong inside Playback options, alongside AVKit's native track controls.")
        capture(app, name: "Native playback after Play Pause")
        XCUIRemote.shared.press(.playPause)
        XCUIRemote.shared.press(.right)
        let soughtForward = expectation(for: NSPredicate { _, _ in
            guard elapsed.exists, let seconds = self.clockSeconds(elapsed.label) else { return false }
            return seconds >= pausedTime + 8
        }, evaluatedWith: player)
        let forwardResult = XCTWaiter.wait(for: [soughtForward], timeout: 6)
        capture(app, name: "Native seek forward")
        XCTAssertEqual(forwardResult, .completed, "Right should seek forward using AVKit's native skip control.")
        let forwardTime = try XCTUnwrap(clockSeconds(elapsed.label))
        XCUIRemote.shared.press(.left)
        let soughtBackward = expectation(for: NSPredicate { _, _ in
            guard elapsed.exists, let seconds = self.clockSeconds(elapsed.label) else { return false }
            return seconds <= forwardTime - 5
        }, evaluatedWith: player)
        let backwardResult = XCTWaiter.wait(for: [soughtBackward], timeout: 6)
        capture(app, name: "Native seek backward")
        XCTAssertEqual(backwardResult, .completed, "Left should seek backward using AVKit's native skip control.")
        XCUIRemote.shared.press(.playPause)
        let finalPosition = try XCTUnwrap(clockSeconds(elapsed.label))
        XCUIRemote.shared.press(.up)
        capture(app, name: "Native transport focus above timeline")
        XCTAssertTrue(player.cells["Playback"].hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.cells.matching(NSPredicate(format: "label BEGINSWITH 'Quality'")).firstMatch
            .waitForExistence(timeout: 3), "Playback options must open as a native menu.")
        capture(app, name: "Playback options menu")
        XCUIRemote.shared.press(.menu)
        let audioControl = player.cells["AVAudibleSettings"]
        if audioControl.exists {
            try focusTransportControl(audioControl, player: player)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.cells.matching(NSPredicate(format: "label BEGINSWITH 'selected, '")).firstMatch
                .waitForExistence(timeout: 3), "The native audio menu should identify the active track.")
            capture(app, name: "Native audio menu")
            XCUIRemote.shared.press(.menu)
        }
        let subtitleControl = player.cells["AVLegibleSettings"]
        if subtitleControl.exists {
            try focusTransportControl(subtitleControl, player: player)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.cells.matching(identifier: "AVSubtitlesOffAction").firstMatch
                .waitForExistence(timeout: 3), "The native subtitle menu must open with its Off control.")
            capture(app, name: "Native subtitle menu")
            XCUIRemote.shared.press(.menu)
        }
        for _ in 0..<3 {
            XCUIRemote.shared.press(.menu)
            if player.waitForNonExistence(timeout: 1) { break }
        }
        XCTAssertTrue(player.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons[detailIdentifier].waitForExistence(timeout: 10))
        let savedPosition = try XCTUnwrap(app.buttons[detailIdentifier].label.split(separator: " ")
            .compactMap { clockSeconds(String($0)) }.first)
        XCTAssertLessThanOrEqual(abs(savedPosition - finalPosition), 2,
                                 "Closing after seeking should save the final position to Plex.")
        capture(app, name: "Returned from playback")
    }

    func testNextEpisodeStartsPlayingAfterPausedQueueSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let homeEpisode = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'media.episode.'")).firstMatch
        guard homeEpisode.waitForExistence(timeout: 20) else {
            throw XCTSkip("Requires an episode on Home with another episode in its season.")
        }
        XCUIRemote.shared.press(.down)
        for _ in 0..<12 {
            if homeEpisode.hasFocus { break }
            let current = try XCTUnwrap(app.buttons.allElementsBoundByIndex.first(where: \.hasFocus))
            XCUIRemote.shared.press(homeEpisode.frame.midX < current.frame.midX ? .left : .right)
        }
        XCTAssertTrue(homeEpisode.hasFocus)
        XCUIRemote.shared.press(.select)
        let picker = app.buttons["season-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'media.episode.'"))
        XCTAssertTrue(row.firstMatch.waitForExistence(timeout: 10))
        guard row.count >= 2 else { throw XCTSkip("Requires at least two episodes in the season.") }
        let firstEpisode = row.element(boundBy: 0)
        let nextEpisode = row.element(boundBy: 1)
        let nextTitle = try XCTUnwrap(nextEpisode.staticTexts.allElementsBoundByIndex.first?.label)
            .split(separator: ".", maxSplits: 1).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        XCTAssertFalse(nextTitle.isEmpty)
        let ratingKey = try XCTUnwrap(firstEpisode.identifier.split(separator: ".").last)
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(containsFocus(firstEpisode))
        XCUIRemote.shared.press(.select)
        let play = app.buttons["detail-play.\(ratingKey)"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            if play.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(play.hasFocus)
        XCUIRemote.shared.press(.select)
        let player = app.otherElements["native-player"]
        XCTAssertTrue(player.waitForExistence(timeout: 30))
        let elapsed = player.otherElements["AXElapsedTime"]
        let started = expectation(for: NSPredicate { _, _ in
            elapsed.exists && (self.clockSeconds(elapsed.label) ?? 0) >= 2
        }, evaluatedWith: player)
        let startedResult = XCTWaiter.wait(for: [started], timeout: 45)
        capture(app, name: "Queue source playback")
        XCTAssertEqual(startedResult, .completed)
        XCUIRemote.shared.press(.playPause)
        let pausedTime = try XCTUnwrap(clockSeconds(elapsed.label))
        let pause = expectation(for: NSPredicate { _, _ in
            (self.clockSeconds(elapsed.label) ?? 0) > pausedTime + 1
        }, evaluatedWith: player)
        pause.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [pause], timeout: 3), .completed)
        XCUIRemote.shared.press(.up)
        try focusTransportControl(player.cells["Queue & Timing"], player: player)
        XCUIRemote.shared.press(.select)
        try selectMenuChoice("Queue", in: app)
        capture(app, name: "Native episode queue menu")
        let next = app.cells.containing(.staticText, identifier: "Next").firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isEnabled)
        XCTAssertTrue(next.staticTexts[nextTitle].exists, "Next must identify the next episode from the season.")
        try selectMenuChoice("Next", in: app)
        let nextVisible = expectation(for: NSPredicate { _, _ in
            player.staticTexts.allElementsBoundByIndex.contains { $0.label.contains(nextTitle) }
        }, evaluatedWith: player)
        let nextResult = XCTWaiter.wait(for: [nextVisible], timeout: 45)
        capture(app, name: "Queue replacement identity")
        XCTAssertEqual(nextResult, .completed, "AVKit must display the selected next episode.")
        let initialTime = try XCTUnwrap(clockSeconds(elapsed.label))
        let advancing = expectation(for: NSPredicate { _, _ in
            elapsed.exists && (self.clockSeconds(elapsed.label) ?? 0) >= initialTime + 3
        }, evaluatedWith: player)
        let advancingResult = XCTWaiter.wait(for: [advancing], timeout: 30)
        capture(app, name: "Next episode decoded and advancing")
        XCTAssertEqual(advancingResult, .completed, "Next must start playback even though the source episode was paused.")
        for _ in 0..<3 {
            XCUIRemote.shared.press(.menu)
            if player.waitForNonExistence(timeout: 1) { break }
        }
        XCTAssertTrue(player.waitForNonExistence(timeout: 5))
    }

    private func focusTransportControl(_ target: XCUIElement, player: XCUIElement) throws {
        for _ in 0..<6 {
            if target.hasFocus { return }
            let current = try XCTUnwrap(player.cells.allElementsBoundByIndex.first(where: \.hasFocus))
            XCUIRemote.shared.press(target.frame.midX < current.frame.midX ? .left : .right)
        }
        XCTAssertTrue(target.hasFocus, "Native transport controls must be reachable with the remote.")
    }

    func testMovieExtrasPlayDirectlyAndReturnToShelf() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let movie = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'media.movie.'")).firstMatch
        guard movie.waitForExistence(timeout: 20) else {
            throw XCTSkip("Requires a signed-in server with a movie on Home.")
        }
        XCUIRemote.shared.press(.down)
        for _ in 0..<12 {
            if movie.hasFocus { break }
            let current = try XCTUnwrap(app.buttons.allElementsBoundByIndex.first(where: \.hasFocus))
            XCUIRemote.shared.press(movie.frame.midX < current.frame.midX ? .left : .right)
        }
        XCTAssertTrue(movie.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail-play.'")).firstMatch
            .waitForExistence(timeout: 15))
        let extras = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'media.clip.'"))
        for _ in 0..<16 {
            if extras.allElementsBoundByIndex.contains(where: \.hasFocus) { break }
            XCUIRemote.shared.press(.down)
        }
        capture(app, name: "Movie discovery shelves")
        XCTAssertFalse(app.staticTexts["Couldn’t Load Extras"].exists)
        XCTAssertFalse(app.staticTexts["Couldn’t Load Related Content"].exists)
        guard let extra = extras.allElementsBoundByIndex.first(where: \.hasFocus) else {
            throw XCTSkip("The selected movie requires a playable extra for this live check.")
        }
        let extraIdentifier = extra.identifier
        let ratingKey = String(extraIdentifier.dropFirst("media.clip.".count))
        XCUIRemote.shared.press(.select)
        let player = app.otherElements["native-player"]
        XCTAssertTrue(player.waitForExistence(timeout: 30), "One Select on an extra must start playback directly.")
        XCTAssertFalse(app.buttons["detail-play.\(ratingKey)"].exists, "Extras must not push their own detail page.")
        let elapsed = player.otherElements["AXElapsedTime"]
        let playing = expectation(for: NSPredicate { _, _ in
            guard elapsed.exists, let seconds = self.clockSeconds(elapsed.label) else { return false }
            return seconds >= 2
        }, evaluatedWith: player)
        let playbackResult = XCTWaiter.wait(for: [playing], timeout: 45)
        capture(app, name: "Extra playback")
        XCTAssertEqual(playbackResult, .completed, "The selected extra must play in AVKit.")
        for _ in 0..<3 {
            XCUIRemote.shared.press(.menu)
            if player.waitForNonExistence(timeout: 1) { break }
        }
        XCTAssertTrue(player.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons[extraIdentifier].waitForExistence(timeout: 5),
                      "Closing an extra must return to its shelf on the originating movie.")
        XCTAssertFalse(app.buttons["detail-play.\(ratingKey)"].exists)
        capture(app, name: "Returned to originating Extras shelf")
        // Verify the effective remote target even if SwiftUI's AX focus flag is stale.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(player.waitForExistence(timeout: 30), "Focus should return to the extra for direct replay.")
        for _ in 0..<3 {
            XCUIRemote.shared.press(.menu)
            if player.waitForNonExistence(timeout: 1) { break }
        }
        XCTAssertTrue(player.waitForNonExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(movie.waitForExistence(timeout: 5), "One Back from the parent detail should return Home.")
    }

    private func clockSeconds(_ value: String) -> Int? {
        let components = value.split(separator: ":")
        guard (2...3).contains(components.count) else { return nil }
        let numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count else { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
#endif
