import SwiftUI

struct StudioArtworkProgressView: View {
    let runtime: StudioGenerationRuntime?
    let referenceURL: URL?
    var queued = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let referenceURL {
                    StudioImageView(url: referenceURL)
                        .frame(height: 240)
                        .accessibilityLabel("Reference image")
                }
                if let engine = runtime?.engine, let approval = engine.approvals.first {
                    StudioCodexApprovalView(engine: engine, approval: approval)
                } else {
                    HStack(spacing: 12) {
                        if queued { Image(systemName: "clock") }
                        else { ProgressView().controlSize(.regular) }
                        Text(queued ? "Queued" : runtime?.isStopping == true ? "Stopping…" : runtime?.engine.activity.nonEmpty ?? "Starting Codex…")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }
                if let engine = runtime?.engine, !engine.transcript.isEmpty {
                    DisclosureGroup("Activity") {
                        Text(engine.transcript).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                }
            }.padding(1)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
