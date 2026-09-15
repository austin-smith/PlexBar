import SwiftUI
import AppKit

struct StudioCodexSettings: View {
    @AppStorage("studio.codexExecutable") private var executable = StudioCodexConnection.defaultExecutable
    @State private var connection = StudioCodexStatusStore()
    @State private var checkRequest = UUID()

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 18) {
            GridRow(alignment: .firstTextBaseline) {
                Text("Status").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        statusLabel
                        Spacer()
                        Button("Refresh", systemImage: "arrow.clockwise") { checkRequest = UUID() }
                            .labelStyle(.iconOnly)
                            .help("Refresh Codex status")
                            .disabled(connection.status == .checking)
                    }
                    if let message = connection.message {
                        Text(message).font(.callout).textSelection(.enabled)
                    }
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            GridRow(alignment: .firstTextBaseline) {
                Text("Account").foregroundStyle(.secondary)
                Text(connection.account ?? (connection.status == .checking ? "Checking…" : "Unavailable"))
                    .textSelection(.enabled)
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            GridRow(alignment: .firstTextBaseline) {
                Text("Installation").foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(connection.version.map { "Version \($0)" } ?? (connection.status == .checking ? "Checking…" : "Version unavailable"))
                        Text(executable).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    Button("Change…", action: chooseExecutable)
                }
            }
        }
        .padding(24)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: checkRequest) { await connection.check(executable: executable) }
        .onChange(of: executable) { checkRequest = UUID() }
    }

    @ViewBuilder private var statusLabel: some View {
        switch connection.status {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking…")
            }
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .needsAttention:
            Label("Needs attention", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .unavailable:
            Label("Unavailable", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose Codex"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { executable = url.path }
    }
}
