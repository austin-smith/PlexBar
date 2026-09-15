import PlexModels
import SwiftUI

struct PlexAutomaticDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: PlexMediaItem
    @Bindable var downloadsStore: PlexDownloadsStore
    @State private var policy: PlexAutomaticDownloadPolicy = .allEpisodes
    @State private var keepsUpToDate = true
    @State private var removesWatchedDownloads = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Episodes", selection: $policy) {
                    ForEach(PlexAutomaticDownloadPolicy.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Download New Episodes", isOn: $keepsUpToDate)
                Toggle("Remove Downloads After Watching", isOn: $removesWatchedDownloads)

                Section("Media") {
                    Text("Uses the quality and subtitle choices in Downloads settings.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(isCreating)
            .overlay {
                if isCreating {
                    ProgressView("Preparing Downloads…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Download", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCreating)
            }
            .padding()
        }
        .frame(width: 520, height: 390)
        .navigationTitle("Download \(item.title)")
        .alert(
            "Download Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown download error.")
        }
    }

    private func create() {
        isCreating = true
        errorMessage = nil
        Task {
            do {
                try await downloadsStore.createAutomaticDownloadRule(
                    for: item,
                    policy: policy,
                    keepsUpToDate: keepsUpToDate,
                    removesWatchedDownloads: removesWatchedDownloads
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}
