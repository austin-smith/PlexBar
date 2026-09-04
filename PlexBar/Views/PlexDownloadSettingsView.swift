import SwiftUI

struct PlexDownloadSettingsView: View {
    @Bindable var settingsStore: PlexSettingsStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Video") {
                    Picker("Download Video Quality", selection: $settingsStore.downloadVideoQuality) {
                        ForEach(PlexDownloadVideoQuality.allCases) { quality in
                            Text(quality.label)
                                .tag(quality)
                        }
                    }
                    .labelsHidden()
                }

                LabeledContent("Music") {
                    Picker("Download Music Quality", selection: $settingsStore.downloadMusicQuality) {
                        ForEach(PlexDownloadMusicQuality.allCases) { quality in
                            Text(quality.label)
                                .tag(quality)
                        }
                    }
                    .labelsHidden()
                }
            } header: {
                Text("Quality")
            } footer: {
                Text("These settings apply only to downloads created after they change.")
            }

            Section {
                LabeledContent("Selected Subtitles") {
                    Picker(
                        "Downloaded Subtitles",
                        selection: $settingsStore.downloadSubtitlePreference
                    ) {
                        ForEach(PlexDownloadSubtitlePreference.allCases) { preference in
                            Text(preference.label)
                                .tag(preference)
                        }
                    }
                    .labelsHidden()
                }
            } header: {
                Text("Subtitles")
            } footer: {
                Text(subtitleExplanation)
            }
        }
        .formStyle(.grouped)
    }

    private var subtitleExplanation: String {
        switch settingsStore.downloadSubtitlePreference {
        case .selectable:
            "Selected subtitles are stored as a switchable text track. Complex formatting may be simplified."
        case .burn:
            "Selected subtitles are rendered permanently into downloaded video."
        case .none:
            "Selected subtitles are not included in new downloads."
        }
    }
}
