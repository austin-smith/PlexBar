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
    let showQueue: () -> Void
    let showInfo: () -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draftPosition: Double?
    @State private var volume: Double = 1
    @State private var isMuted = false
    @State private var showsVolume = false
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable {
        case timeline, previous, backward, playPause, forward, next
        case volumePopover, mute, volume, queue, options, pictureInPicture, fullScreen
    }

    private var duration: Double? {
        let value = session.engine.duration ?? session.presentation.plan.duration
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private var isVisible: Bool {
        state.isVisible(status: session.engine.status, voiceOverEnabled: voiceOverEnabled)
    }

    var body: some View {
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
        .environment(\.colorScheme, .dark)
        .labelStyle(.iconOnly)
        .buttonStyle(PlexPlayerControlButtonStyle())
        .font(.system(size: 15, weight: .medium))
        .onHover { hovering in
            state.isHoveringControls = hovering
            state.reveal()
        }
        .onChange(of: showsVolume) {
            state.isPopoverPresented = showsVolume
            state.reveal()
        }
        .onChange(of: focusedControl) { state.hasKeyboardFocus = focusedControl != nil }
        .onChange(of: session.presentation.id) {
            draftPosition = nil
            state.isScrubbing = false
            state.reveal()
        }
        .onChange(of: ObjectIdentifier(session.engine.player), initial: true) {
            volume = Double(session.engine.player.volume)
            isMuted = session.engine.player.isMuted
        }
        .onDisappear {
            state.hasKeyboardFocus = false
            state.isHoveringControls = false
            state.isScrubbing = false
            state.isPopoverPresented = false
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isVisible)
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
            Slider(
                value: Binding(
                    get: { min(max(displayPosition, 0), duration ?? 1) },
                    set: { value in
                        if state.isScrubbing { draftPosition = value }
                        else { session.seek(to: value) }
                    }
                ),
                in: 0...(duration ?? 1),
                onEditingChanged: { editing in
                    if editing {
                        draftPosition = session.engine.position
                        state.isScrubbing = true
                    } else {
                        if let draftPosition { session.seek(to: draftPosition) }
                        draftPosition = nil
                        state.isScrubbing = false
                        state.reveal()
                    }
                }
            )
            .tint(.white)
            .controlSize(.small)
            .disabled(!coordinator.canSeek || duration == nil)
            .focused($focusedControl, equals: .timeline)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(PlexPlayerTimeDisplay.string(displayPosition)) of \(PlexPlayerTimeDisplay.string(duration ?? .nan))")
            Text(duration.map { "−" + PlexPlayerTimeDisplay.string(max(0, $0 - displayPosition)) } ?? "--:--")
                .fixedSize()
                .accessibilityLabel("Remaining time")
        }
        .font(.system(.caption, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.7))
    }

    private var displayPosition: Double {
        draftPosition ?? session.engine.position
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
            showsVolume.toggle()
        }
        .help("Adjust Volume")
        .accessibilityValue("\(Int((isMuted ? 0 : volume) * 100)) percent")
        .focused($focusedControl, equals: .volumePopover)
        .popover(isPresented: $showsVolume, arrowEdge: .top) {
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
                .help("Show Up Next")
                .focused($focusedControl, equals: .queue)
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
