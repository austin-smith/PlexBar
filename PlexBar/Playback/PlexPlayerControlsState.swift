import PlexClientKit
import Observation
import Foundation

@MainActor
@Observable
final class PlexPlayerControlsState {
    var isPointerActive = true
    private(set) var isKeyboardNavigating = false
    var hasKeyboardFocus = false
    var isTimelineFocused = false
    let scrub = PlexPlayerScrubState()
    var isScrubbing: Bool { scrub.isActive }
    var isMenuTracking = false
    var isPopoverPresented = false
    @ObservationIgnored private let inactivityDelay: Duration
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    init(inactivityDelay: Duration = .seconds(3)) {
        self.inactivityDelay = inactivityDelay
    }

    func pointerActivity() {
        isKeyboardNavigating = false
        reveal()
    }

    func keyboardActivity(isNavigation: Bool) {
        if isNavigation { isKeyboardNavigating = true }
        reveal()
    }

    func reveal() {
        isPointerActive = true
        hideTask?.cancel()
        let delay = inactivityDelay
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            self?.isPointerActive = false
            self?.hideTask = nil
        }
    }

    func stop() {
        hideTask?.cancel()
        hideTask = nil
    }

    func isVisible(status: PlexPlaybackStatus, voiceOverEnabled: Bool) -> Bool {
        // Focus keeps controls available for Tab navigation, but a return to
        // pointer input allows idle playback to hide them again.
        isPointerActive || (isKeyboardNavigating && (hasKeyboardFocus || isTimelineFocused))
            || isScrubbing || isMenuTracking || isPopoverPresented
            || status != .playing || voiceOverEnabled
    }
}

enum PlexPlayerTimeDisplay {
    static func string(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "--:--" }
        let seconds = Int(seconds)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}
