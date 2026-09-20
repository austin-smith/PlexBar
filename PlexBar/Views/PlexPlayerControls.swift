import AVKit
import SwiftUI

struct PlexPlayerControls: View {
    let session: PlexPlayerSessionModel
    let coordinator: PlexPlayerCoordinator
    let settingsStore: PlexSettingsStore
    let presentation: PlexPlayerPresentationController
    let mediaOptions: PlexPlayerMediaOptions
    let state: PlexPlayerControlsState
    let lifecycle: PlexPlayerPresentationLifecycle
    let isInteractionEnabled: Bool
    let showQueue: () -> Void
    let showInfo: () -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var volume: Double = 1
    @State private var isMuted = false
    @State private var availablePopoverHeight: CGFloat = 420
    @State private var preview = PlexPlaybackPreviewStore()
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable {
        case previous, backward, playPause, forward, next
        case volumePopover, mute, volume, queue, options, pictureInPicture, fullScreen
    }

    private var duration: Double? {
        let value = session.engine.duration ?? session.presentation.plan.duration
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private var isVisible: Bool {
        isInteractionEnabled && state.isVisible(status: session.engine.status, voiceOverEnabled: voiceOverEnabled)
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            controlPanel
        }
        // Fade the complete glass container so its native effect and controls
        // share the same visibility, hit testing, and accessibility lifetime.
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(reduceMotion ? nil : .easeOut(duration: isVisible ? 0.1 : 0.3), value: isVisible)
    }

    private var controlPanel: some View {
        VStack(spacing: 6) {
            contentHeader
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    utilityControls
                        .frame(maxWidth: .infinity, alignment: .leading)
                    transportControls
                        .fixedSize()
                    presentationControls
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                timeline
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 560)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .overlayPreferenceValue(PlexPlayerTimelineAnchorKey.self) { anchor in
            if let anchor, let position = preview.position, isVisible {
                GeometryReader { geometry in
                    let bounds = geometry[anchor]
                    let track = PlexPlayerTimelineGeometry(width: bounds.width, duration: duration ?? 0)
                    let x = bounds.minX + PlexPlayerTimelineGeometry.inset + track.x(for: position)
                    let halfWidth = PlexPlayerTimelinePreview.width / 2
                    let center = min(max(x, halfWidth + 8), geometry.size.width - halfWidth - 8)
                    Color.clear.frame(height: 0)
                        .overlay(alignment: .bottomLeading) {
                            PlexPlayerTimelinePreview(store: preview)
                                .fixedSize()
                                .offset(x: center - halfWidth, y: -12)
                        }
                }
                .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .dark)
        .labelStyle(.iconOnly)
        .buttonStyle(PlexPlayerControlButtonStyle())
        .font(.system(size: 15, weight: .medium))
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.frame(in: .named("playerStage")).minY
        } action: { top in
            availablePopoverHeight = max(120, top - 16)
        }
        .onChange(of: state.isKeyboardNavigating) {
            if !state.isKeyboardNavigating { focusedControl = nil }
        }
        .onChange(of: state.isScrubbing) { state.reveal() }
        .onChange(of: state.presentedPopover) { previous, current in
            preview.hide()
            state.reveal()
            if current == nil, isInteractionEnabled, state.isKeyboardNavigating {
                focusedControl = previous == .upNext ? .queue : .volumePopover
            }
        }
        .onChange(of: isInteractionEnabled) {
            if !isInteractionEnabled { state.dismissPopover() }
        }
        .onChange(of: lifecycle.isFullScreenTransitioning) {
            if lifecycle.isFullScreenTransitioning { state.dismissPopover() }
        }
        .onChange(of: focusedControl) { state.hasKeyboardFocus = focusedControl != nil }
        .onChange(of: session.playbackPreviewSource) { preview.configure(session.playbackPreviewSource) }
        .onChange(of: isVisible) {
            if !isVisible {
                preview.hide()
                focusedControl = nil
            }
        }
        .onChange(of: session.presentation.id) {
            state.scrub.reset()
            state.reveal()
        }
        .onChange(of: ObjectIdentifier(session.engine.player), initial: true) {
            volume = Double(session.engine.player.volume)
            isMuted = session.engine.player.isMuted
        }
        .onDisappear {
            preview.hide()
            state.hasKeyboardFocus = false
            state.scrub.reset()
            state.isTimelineFocused = false
            state.dismissPopover()
        }
    }

    private var contentHeader: some View {
        let metadata = PlexPlayerContentMetadata(
            item: session.presentation.item,
            source: session.presentation.plan.source
        )
        return HStack(spacing: 8) {
            if let title = metadata.title {
                Text(title)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.95))
            }
            ForEach(metadata.details, id: \.self) { detail in
                Text(detail)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.tail)
        .accessibilityElement(children: .combine)
        .help(([metadata.title].compactMap { $0 } + metadata.details).joined(separator: "\n"))
    }

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(PlexPlayerTimeDisplay.string(displayPosition))
                .fixedSize()
                .accessibilityLabel("Elapsed time")
            PlexPlayerTimeline(
                position: min(max(displayPosition, 0), duration ?? 1),
                duration: duration ?? 0,
                scrub: state.scrub,
                onCommit: { value in
                    session.seek(to: value)
                    state.reveal()
                },
                onPreview: { position in
                    guard session.presentation.plan.mediaKind == .video else { return }
                    if let position {
                        preview.show(at: position, source: session.playbackPreviewSource)
                    } else {
                        preview.hide()
                    }
                },
                isKeyboardNavigating: state.isKeyboardNavigating,
                isControlsVisible: isVisible,
                onFocusChanged: { state.isTimelineFocused = $0 }
            )
            .disabled(!coordinator.canSeek || duration == nil)
            .anchorPreference(key: PlexPlayerTimelineAnchorKey.self, value: .bounds) { $0 }
            Text(duration.map { "−" + PlexPlayerTimeDisplay.string(max(0, $0 - displayPosition)) } ?? "--:--")
                .fixedSize()
                .accessibilityLabel("Remaining time")
        }
        .font(.system(.caption, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.7))
    }

    private var displayPosition: Double {
        state.scrub.position ?? session.engine.position
    }

    private var transportControls: some View {
        HStack(spacing: 4) {
            Button("Previous", systemImage: "backward.end.fill", action: coordinator.goPrevious)
                .disabled(!coordinator.canGoPrevious)
                .help("Previous Item (⌘←)")
                .focused($focusedControl, equals: .previous)
            Button("Back 10 Seconds", systemImage: "gobackward.10", action: coordinator.skipBackward)
                .disabled(!coordinator.canSeek)
                .help("Back 10 Seconds (←)")
                .focused($focusedControl, equals: .backward)
            Button(action: coordinator.togglePlayback) {
                ZStack {
                    Image(systemName: coordinator.transportAction == .pause ? "pause.fill" : "play.fill")
                        .opacity(isWaitingForPlayback ? 0 : 1)
                    if isWaitingForPlayback {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                }
                .font(.system(size: 23, weight: .semibold))
                .frame(width: 40, height: 36)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { coordinator.togglePlayback() }
            .accessibilityLabel(coordinator.transportAction == .pause ? "Pause" : "Play")
            .accessibilityValue(isWaitingForPlayback ? (session.engine.status == .buffering ? "Buffering" : "Loading") : "")
            .disabled(coordinator.transportAction == nil)
            .help("Play/Pause (Space)")
            .focused($focusedControl, equals: .playPause)
            Button("Forward 10 Seconds", systemImage: "goforward.10", action: coordinator.skipForward)
                .disabled(!coordinator.canSeek)
                .help("Forward 10 Seconds (→)")
                .focused($focusedControl, equals: .forward)
            Button("Next", systemImage: "forward.end.fill", action: coordinator.goNext)
                .disabled(!coordinator.canGoNext)
                .help(nextLabel + " (⌘→)")
                .accessibilityLabel(nextLabel)
                .focused($focusedControl, equals: .next)
        }
    }

    private var isWaitingForPlayback: Bool {
        session.isLoading || session.engine.status == .buffering || session.engine.status == .preparing
    }

    private var volumeSymbol: String {
        if isMuted || volume == 0 { return "speaker.slash.fill" }
        return volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }

    private var volumeButton: some View {
        Button("Volume", systemImage: volumeSymbol) {
            state.togglePopover(.volume)
        }
        .help("Adjust Volume")
        .accessibilityValue("\(Int((isMuted ? 0 : volume) * 100)) percent")
        .focused($focusedControl, equals: .volumePopover)
        .popover(isPresented: popoverBinding(.volume), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Volume")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("\(Int((isMuted ? 0 : volume) * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "speaker.slash.fill" : "speaker.fill") {
                        isMuted.toggle()
                        session.engine.player.isMuted = isMuted
                    }
                    .help(isMuted ? "Unmute" : "Mute")
                    .focused($focusedControl, equals: .mute)
                    PlexPlayerVolumeSlider(value: Binding(
                        get: { isMuted ? 0 : volume },
                        set: {
                            volume = $0
                            isMuted = false
                            session.engine.player.isMuted = false
                            session.engine.player.volume = Float($0)
                        }
                    ))
                    .frame(width: 180, height: 24)
                    .focused($focusedControl, equals: .volume)
                    Image(systemName: "speaker.wave.3.fill")
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .labelStyle(.iconOnly)
            .buttonStyle(PlexPlayerControlButtonStyle())
            .environment(\.colorScheme, .dark)
        }
    }

    private var utilityControls: some View {
        HStack(spacing: 2) {
            volumeButton
            Button("Up Next", systemImage: "list.bullet", action: showQueue)
                .help(state.presentedPopover == .upNext ? "Hide Up Next" : "Show Up Next")
                .accessibilityValue(state.presentedPopover == .upNext ? "Expanded" : "Collapsed")
                .background {
                    if state.presentedPopover == .upNext {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.14))
                    }
                }
                .focused($focusedControl, equals: .queue)
                .popover(isPresented: popoverBinding(.upNext), arrowEdge: .top) {
                    PlexUpNextPopover(session: session, maximumHeight: availablePopoverHeight)
                        .environment(\.colorScheme, .dark)
                }
            PlexPlaybackOptionsMenu(
                session: session,
                settingsStore: settingsStore,
                mediaOptions: mediaOptions,
                coordinator: coordinator,
                showInfo: showInfo
            )
            .menuIndicator(.hidden)
            .focused($focusedControl, equals: .options)
        }
    }

    private func popoverBinding(_ popover: PlexPlayerPopover) -> Binding<Bool> {
        Binding(
            get: { state.presentedPopover == popover },
            set: { isPresented in
                if !isPresented { state.dismissPopover(popover) }
            }
        )
    }

    private var presentationControls: some View {
        HStack(spacing: 2) {
            PlexPlaybackRoutePicker(player: session.engine.player)
                .frame(width: 32, height: 32)
                .help("Choose Playback Destination")
            if session.presentation.plan.mediaKind == .video {
                Button(
                    lifecycle.isPictureInPictureActive ? "Exit Picture in Picture" : "Picture in Picture",
                    systemImage: lifecycle.isPictureInPictureActive ? "pip.exit" : "pip.enter",
                    action: presentation.togglePictureInPicture
                )
                .disabled(!presentation.canStartPictureInPicture && !lifecycle.isPictureInPictureActive)
                .help(lifecycle.isPictureInPictureActive ? "Exit Picture in Picture" : "Picture in Picture")
                .focused($focusedControl, equals: .pictureInPicture)
                Button(
                    lifecycle.isFullScreenActive ? "Exit Full Screen" : "Full Screen",
                    systemImage: lifecycle.isFullScreenActive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    action: presentation.toggleFullScreen
                )
                .disabled(lifecycle.isFullScreenTransitioning)
                .help(lifecycle.isFullScreenActive ? "Exit Full Screen (Esc)" : "Full Screen (F)")
                .focused($focusedControl, equals: .fullScreen)
            }
        }
    }

    private var nextLabel: String {
        guard let item = session.queuePresentation?.upcomingItems.first else { return "Next Item" }
        let action = item.type == "episode" ? "Next Episode" : "Next Item"
        return "\(action): \(item.title)"
    }
}

/// Equal hit targets and restrained feedback keep the transport easy to scan.
private struct PlexPlayerControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Control(configuration: configuration)
    }

    private struct Control: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .frame(minWidth: 32, minHeight: 32)
                .foregroundStyle(.white.opacity(isEnabled ? 0.95 : 0.3))
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(isEnabled ? (configuration.isPressed ? 0.18 : isHovered ? 0.1 : 0) : 0))
                }
                .contentShape(.rect)
                .onHover { isHovered = $0 }
        }
    }
}
