import SwiftUI

struct StudioArtworkStyleSettings: View {
    let store: StudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var instructions: StudioArtworkInstructions?
    @State private var original: StudioArtworkInstructions?
    @State private var selectedSection = StudioArtworkInstructions.Section.referenceArtwork
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Prompt", selection: $selectedSection) {
                ForEach(StudioArtworkInstructions.Section.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .frame(maxWidth: .infinity)

            TextEditor(text: Binding(
                get: { instructions?[keyPath: selectedSection.keyPath] ?? "" },
                set: { instructions?[keyPath: selectedSection.keyPath] = $0 }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(height: 300)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.separator, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel(selectedSection.title)
            .disabled(instructions == nil)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).buttonStyle(.borderedProminent)
                    .disabled(instructions == nil)
            }
        }.padding(24)
            .onAppear {
                do {
                    let loaded = try store.loadArtworkInstructions()
                    instructions = loaded
                    original = loaded
                    errorMessage = nil
                } catch {
                    instructions = nil
                    original = nil
                    errorMessage = error.localizedDescription
                }
            }
    }

    private func save() {
        guard let instructions, let original else { return }
        do {
            try store.saveArtworkInstructions(instructions, replacing: original)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
