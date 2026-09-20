import PlexClientKit
import SwiftUI

struct TVSettingsView: View {
    @Environment(TVAppStore.self) private var store
    @State private var showsSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            settingsIndex
                .navigationDestination(for: TVSettingsDestination.self) { destination in
                    settingsPage(destination)
                }
        }
        .confirmationDialog(
            "Sign Out of PlexBar?",
            isPresented: $showsSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await store.logout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PlexBar will remove this account and its saved server from this Apple TV.")
        }
    }

    private var settingsIndex: some View {
        TVSettingsForm {
            Section("Plex") {
                NavigationLink(value: TVSettingsDestination.server) {
                    TVSettingsNavigationRow(
                        title: "Plex Server",
                        systemImage: "server.rack",
                        value: store.serverName
                    )
                }
            }

            Section("Playback") {
                ForEach(TVSettingsDestination.playbackDestinations) { destination in
                    NavigationLink(value: destination) {
                        Label(destination.title, systemImage: destination.systemImage)
                    }
                }
            }

            Section("Account") {
                Button(
                    "Sign Out",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    role: .destructive
                ) {
                    showsSignOutConfirmation = true
                }
            }
        }
        .navigationTitle("Settings")
        .accessibilityLabel("Settings")
    }

    private func settingsPage(_ destination: TVSettingsDestination) -> some View {
        TVSettingsForm {
            switch destination {
            case .server:
                connectionSections
            case .video:
                videoSections
            case .audio:
                audioSections
            case .subtitles:
                subtitleSections
            case .advanced:
                advancedSections
            }
        }
        .navigationTitle(destination.title)
    }

    @ViewBuilder
    private var connectionSections: some View {
        Section("Current Server") {
            LabeledContent("Name", value: store.serverName)
            if let connectionKind = store.connection?.kind {
                LabeledContent("Connection", value: connectionKind.displayName)
            }
        }

        Section {
            Button("Refresh Libraries", systemImage: "arrow.clockwise") {
                Task { await store.refreshAll() }
            }
            Button("Change Server", systemImage: "arrow.triangle.branch") {
                Task { await store.chooseServer() }
            }
        }
    }

    @ViewBuilder
    private var videoSections: some View {
        @Bindable var store = store

        Section {
            Picker(
                store.automaticallyAdjustVideoQuality
                    ? "Home Starting Quality"
                    : "Home Streaming Quality",
                selection: $store.localVideoQuality
            ) {
                ForEach(PlexVideoQuality.allCases) { quality in
                    Text(quality.label).tag(quality)
                }
            }
            Picker(
                store.automaticallyAdjustVideoQuality
                    ? "Remote Starting Quality"
                    : "Remote Streaming Quality",
                selection: $store.remoteVideoQuality
            ) {
                ForEach(PlexVideoQuality.allCases) { quality in
                    Text(quality.label).tag(quality)
                }
            }
            Toggle(
                "Play Smaller Remote Videos at Original Quality",
                isOn: $store.playSmallerVideosAtOriginalQuality
            )
            Toggle("Automatically Adjust Quality", isOn: $store.automaticallyAdjustVideoQuality)
            Toggle("Suggest Quality Changes", isOn: $store.qualitySuggestionsEnabled)
                .disabled(store.automaticallyAdjustVideoQuality)
        } header: {
            Text("Streaming Quality")
        } footer: {
            Text(
                "Converted video starts at the selected quality. When automatic adjustment is on, Plex and Apple TV adapt the stream as connection conditions change. Original-quality playback is unchanged."
            )
        }

        Section("Presentation") {
            Picker("Video Scaling", selection: $store.videoScalingMode) {
                ForEach(PlexVideoScalingMode.allCases) { scalingMode in
                    Text(scalingMode.label).tag(scalingMode)
                }
            }
            Picker("Cinema Experience", selection: $store.cinemaPreplayPreference) {
                ForEach(PlexCinemaPreplayPreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            Picker(
                "Rewind on Resume",
                selection: Binding(
                    get: { store.rewindOnResume.seconds },
                    set: { store.rewindOnResume = PlexRewindOnResume(seconds: $0) }
                )
            ) {
                ForEach(PlexRewindOnResume.secondsRange, id: \.self) { seconds in
                    Text(PlexRewindOnResume(seconds: seconds).label).tag(seconds)
                }
            }
            .accessibilityLabel("Rewind on Resume")
            .accessibilityValue(store.rewindOnResume.label)
        }

        Section("Episode Playback") {
            markerBehaviorPicker("Skip Intros", selection: $store.skipIntroBehavior)
            markerBehaviorPicker("Skip Ads", selection: $store.skipAdsBehavior)
            markerBehaviorPicker("Skip Credits", selection: $store.skipCreditsBehavior)
            Toggle("Automatically Play Next Episode", isOn: $store.autoplayNextEpisode)
            if store.autoplayNextEpisode {
                Picker("Play Next Episode", selection: $store.autoplayCountdown) {
                    ForEach(PlexAutoplayCountdown.allCases) { countdown in
                        Text(countdown.label).tag(countdown)
                    }
                }
                Picker("Are You Still Watching?", selection: $store.passoutProtection) {
                    ForEach(PlexPassoutProtection.allCases) { protection in
                        Text(protection.label).tag(protection)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var audioSections: some View {
        @Bindable var store = store

        Section {
            Picker("Remote Music Quality", selection: $store.remoteMusicQuality) {
                ForEach(PlexMusicQuality.allCases) { quality in
                    Text(quality.label).tag(quality)
                }
            }
        } footer: {
            Text(
                "Music on your home network plays at original quality. This limit applies only when streaming from a remote Plex server."
            )
        }

        Section {
            Picker("Multichannel Audio Boost", selection: $store.audioBoost) {
                ForEach(PlexAudioBoost.allCases) { boost in
                    Text("\(boost.label) · \(boost.percentageLabel)").tag(boost)
                }
            }
        } footer: {
            Text(
                "Boost applies only when Plex converts multichannel audio to stereo. Original surround and stereo playback are unchanged."
            )
        }
    }

    @ViewBuilder
    private var subtitleSections: some View {
        @Bindable var store = store

        Section {
            Picker("Subtitle Size", selection: $store.subtitleSize) {
                ForEach(PlexSubtitleSize.allCases) { size in
                    Text("\(size.label) · \(size.percentageLabel)").tag(size)
                }
            }
            Toggle("Auto-Sync Compatible Subtitles", isOn: $store.automaticallySyncSubtitles)
        } footer: {
            Text(
                "When Plex has analyzed the video and the selected subtitle supports it, auto-sync aligns subtitle timing to detected dialogue."
            )
        }

        Section {
            Picker("Burn Subtitles", selection: $store.subtitleBurnMode) {
                ForEach(PlexSubtitleBurnMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
        } footer: {
            Text(store.subtitleBurnMode.explanation)
        }
    }

    @ViewBuilder
    private var advancedSections: some View {
        @Bindable var store = store

        Section {
            Toggle("Allow Direct Play", isOn: $store.allowsDirectPlay)
            Toggle("Allow Direct Stream", isOn: $store.allowsDirectStream)
            Toggle("Force Direct Play", isOn: $store.forceDirectPlay)
                .disabled(!store.allowsDirectPlay)
        } footer: {
            Text(
                "Force Direct Play bypasses the server decision only when this Apple TV proves the exact file is natively compatible. Changes apply to the next item or playback reload."
            )
        }
    }

    private func markerBehaviorPicker(
        _ title: String,
        selection: Binding<PlexPlaybackMarkerBehavior>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(PlexPlaybackMarkerBehavior.allCases) { behavior in
                Text(behavior.label).tag(behavior)
            }
        }
    }
}

private enum TVSettingsDestination: String, Hashable, Identifiable {
    case server
    case video
    case audio
    case subtitles
    case advanced

    static let playbackDestinations: [TVSettingsDestination] = [
        .video,
        .audio,
        .subtitles,
        .advanced,
    ]

    var id: Self { self }

    var title: String {
        switch self {
        case .server: "Plex Server"
        case .video: "Video"
        case .audio: "Audio"
        case .subtitles: "Subtitles"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .server: "server.rack"
        case .video: "play.tv.fill"
        case .audio: "waveform"
        case .subtitles: "captions.bubble.fill"
        case .advanced: "slider.horizontal.3"
        }
    }
}

private struct TVSettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            Form {
                content
            }
            .safeAreaPadding(.horizontal, proxy.size.width / 5)
            .safeAreaPadding(.vertical)
        }
    }
}

private struct TVSettingsNavigationRow: View {
    let title: String
    let systemImage: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
