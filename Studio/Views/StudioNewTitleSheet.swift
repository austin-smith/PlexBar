import SwiftUI
import AppKit

struct StudioNewTitleSheet: View {
    let store: StudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind = "movie"
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add a title").font(.title2.bold())
            Text("Codex researches the title and prepares a sourced catalog draft for review.").foregroundStyle(.secondary)
            Form {
                TextField("Title", text: $title)
                Picker("Type", selection: $kind) {
                    Text("Movie").tag("movie")
                    Text("TV show").tag("show")
                    Text("Audiobook").tag("audiobook")
                }
                TextField("Source links or notes", text: $notes, axis: .vertical).lineLimit(5...9)
            }.formStyle(.grouped)
            HStack {
                Text("Review the draft in History when it completes.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Research with Codex") { store.research(title: title, kind: kind, notes: notes); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 640)
    }
}
