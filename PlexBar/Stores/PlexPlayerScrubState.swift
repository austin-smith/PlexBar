import Observation

/// Shares a pointer gesture with keyboard cancellation without requiring focus.
@MainActor
@Observable
final class PlexPlayerScrubState {
    private enum Phase {
        case idle, dragging(Double), cancelled
    }

    private var phase: Phase = .idle

    var isActive: Bool {
        if case .idle = phase { return false }
        return true
    }

    var position: Double? {
        if case .dragging(let position) = phase { return position }
        return nil
    }

    func begin(at position: Double) { phase = .dragging(position) }

    func update(to position: Double) {
        guard case .dragging = phase else { return }
        phase = .dragging(position)
    }

    func cancel() {
        guard isActive else { return }
        // Keep consuming this gesture and Escape repeats until mouse-up.
        phase = .cancelled
    }

    func finish(at position: Double) -> Double? {
        defer { reset() }
        guard case .dragging = phase else { return nil }
        return position
    }

    func reset() { phase = .idle }
}
