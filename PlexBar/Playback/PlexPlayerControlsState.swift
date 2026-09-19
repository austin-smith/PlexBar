import Observation
import Foundation

@MainActor
@Observable
final class PlexPlayerControlsState {
    var isPointerActive = true
    var isHoveringControls = false
    var hasKeyboardFocus = false
    var isScrubbing = false
    var isMenuTracking = false
    var isPopoverPresented = false
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func reveal() {
        isPointerActive = true
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.isPointerActive = false
            self?.hideTask = nil
        }
    }

    func stop() {
        hideTask?.cancel()
        hideTask = nil
    }

    func isVisible(status: PlexPlaybackStatus, voiceOverEnabled: Bool) -> Bool {
        isPointerActive || isHoveringControls || hasKeyboardFocus || isScrubbing || isMenuTracking || isPopoverPresented
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
