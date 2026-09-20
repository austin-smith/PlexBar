import SwiftUI
import AppKit

struct StudioRecordSheet: View {
    let store: StudioStore
    let record: StudioCatalogRecord
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""
    @State private var year = ""
    @State private var error: String?
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit metadata").font(.title2.bold())
            Form {
                TextField("Title", text: $title)
                TextField("Year", text: $year)
                TextField("Summary", text: $summary, axis: .vertical).lineLimit(6...12)
            }.formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Advanced Fields…") { showAdvanced = true }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Changes") {
                    do {
                        var metadata = record.metadata
                        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StudioError.invalid("Enter a title.") }
                        if !year.isEmpty && Int(year) == nil { throw StudioError.invalid("Enter a whole year, or leave it empty.") }
                        metadata["title"] = .string(title)
                        metadata["summary"] = .string(summary)
                        metadata["year"] = Int(year).map(StudioJSON.integer)
                        try store.applyMetadataJSON(metadata.prettyPrinted, recordID: record.id)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 620)
            .onAppear { title = record.title; summary = record.metadata["summary"]?.string ?? ""; year = record.metadata["year"]?.integer.map(String.init) ?? "" }
            .sheet(isPresented: $showAdvanced) {
                StudioJSONSheet(title: "Plex Metadata", initialText: record.metadata.prettyPrinted) { text in
                    try store.applyMetadataJSON(text, recordID: record.id)
                    dismiss()
                }
            }
    }
}
