import SwiftUI

/// One coordinate mapping drives the rail, thumb, hover preview and committed seek.
struct PlexPlayerTimeline: View {
    let position: Double
    let duration: Double
    let scrub: PlexPlayerScrubState
    let onCommit: (Double) -> Void
    let onPreview: (Double?) -> Void
    let isKeyboardNavigating: Bool
    let isControlsVisible: Bool
    let onFocusChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @GestureState private var isDragging = false
    @State private var hoverPosition: Double?
    @State private var hasStartedDrag = false

    var body: some View {
        GeometryReader { geometry in
            let track = PlexPlayerTimelineGeometry(width: geometry.size.width, duration: duration)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                    .frame(height: 4)
                Capsule().fill(.white.opacity(isEnabled ? 0.95 : 0.3))
                    .frame(width: track.x(for: position), height: 4)
                Circle().fill(.white.opacity(isEnabled ? 1 : 0.3))
                    .frame(width: 10, height: 10)
                    .offset(x: track.x(for: position) - 5)
            }
            .padding(.horizontal, PlexPlayerTimelineGeometry.inset)
            .frame(height: 24)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .updating($isDragging) { _, dragging, _ in dragging = true }
                .onChanged { value in
                    if !hasStartedDrag {
                        hasStartedDrag = true
                        guard isEnabled else { return }
                        scrub.begin(at: track.time(at: value.location.x))
                    }
                    guard isEnabled else { return }
                    let time = track.time(at: value.location.x)
                    scrub.update(to: time)
                    onPreview(scrub.position)
                }
                .onEnded { value in
                    defer { hasStartedDrag = false }
                    guard isEnabled, let time = scrub.finish(at: track.time(at: value.location.x)) else {
                        scrub.reset()
                        onPreview(nil)
                        return
                    }
                    hoverPosition = CGRect(origin: .zero, size: geometry.size).contains(value.location) ? time : nil
                    onCommit(time)
                    onPreview(hoverPosition)
                }
            )
            .onContinuousHover { phase in
                guard isEnabled else { return }
                switch phase {
                case .active(let location): hoverPosition = track.time(at: location.x)
                case .ended: hoverPosition = nil
                }
                if !isDragging { onPreview(hoverPosition) }
            }
        }
        .frame(height: 24)
        .contentShape(.capsule)
        // Pointer scrubbing does not acquire focus; Tab navigation still can.
        .focusable(isEnabled, interactions: .activate)
        .focused($isFocused)
        .accessibilityRepresentation {
            Slider(value: Binding(get: { position }, set: { onCommit($0) }), in: 0...max(duration, 1), step: 10)
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(PlexPlayerTimeDisplay.string(position)) of \(PlexPlayerTimeDisplay.string(duration))")
        }
        .onChange(of: isDragging) { _, dragging in
            if !dragging, scrub.isActive { scrub.reset(); onPreview(nil) }
            if !dragging { hasStartedDrag = false }
        }
        .onChange(of: scrub.position) {
            if scrub.isActive, scrub.position == nil { onPreview(nil) }
        }
        .onChange(of: isFocused) { onFocusChanged(isFocused) }
        .onChange(of: isControlsVisible) {
            if !isControlsVisible { isFocused = false }
        }
        .onChange(of: isKeyboardNavigating) {
            if !isKeyboardNavigating { isFocused = false }
        }
        .onChange(of: isEnabled) {
            if !isEnabled { hoverPosition = nil; scrub.cancel(); onPreview(nil) }
        }
        .onDisappear { scrub.reset(); onPreview(nil); onFocusChanged(false) }
    }
}

struct PlexPlayerTimelineGeometry {
    static let inset: CGFloat = 5
    let width: CGFloat
    let duration: Double
    var trackWidth: CGFloat { max(0, width - Self.inset * 2) }

    func time(at x: CGFloat) -> Double {
        guard trackWidth > 0, duration.isFinite, duration > 0, x.isFinite else { return 0 }
        return min(max((x - Self.inset) / trackWidth, 0), 1) * duration
    }

    /// Position within the inset track, not the entire hit region.
    func x(for time: Double) -> CGFloat {
        guard duration.isFinite, duration > 0, time.isFinite else { return 0 }
        return min(max(time / duration, 0), 1) * trackWidth
    }
}

struct PlexPlayerTimelineAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct PlexPlayerTimelinePreview: View {
    static let width: CGFloat = 172
    let store: PlexPlaybackPreviewStore

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Color.black.opacity(0.9)
                if let image = store.image {
                    Image(decorative: image.image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else if store.isLoading {
                    ProgressView().controlSize(.small)
                } else if let message = store.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(10)
                }
            }
            .frame(width: 160, height: 90)
            .clipShape(.rect(cornerRadius: 6))
            Text(PlexPlayerTimeDisplay.string(store.position ?? 0))
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(6)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
