import SwiftUI

struct StudioPromptPreview: View {
    let prompt: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Prompt Preview").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(prompt).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(24).frame(width: 660, height: 560)
    }
}
