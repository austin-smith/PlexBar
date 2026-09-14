import SwiftUI
import AppKit

struct StudioJSONSheet: View {
    let title: String
    let initialText: String
    let save: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            Text("Saving updates PlexBar’s mock content after validation.").foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).border(.quaternary)
            if let error { ScrollView { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }.frame(maxHeight: 100) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply Changes") {
                    do { try save(text); dismiss() } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 740, height: 660).onAppear { text = initialText }
    }
}
