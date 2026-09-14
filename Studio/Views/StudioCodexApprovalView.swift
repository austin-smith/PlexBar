import SwiftUI

struct StudioCodexApprovalView: View {
    let engine: StudioCodexEngine
    let approval: StudioCodexApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Codex requests permission", systemImage: "hand.raised")
                .font(.headline)
            ScrollView {
                Text(approval.details).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 100)
            HStack {
                Spacer()
                Button("Decline") { engine.answer(approval, allow: false) }
                Button("Allow Once") { engine.answer(approval, allow: true) }
            }
        }
    }
}
