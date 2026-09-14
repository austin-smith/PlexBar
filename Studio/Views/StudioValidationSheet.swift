import SwiftUI
import AppKit

struct StudioValidationSheet: View {
    let issues: [StudioValidationIssue]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(issues.isEmpty ? "Content checks passed" : "Review these issues", systemImage: issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle")
                .font(.title2.bold()).foregroundStyle(issues.isEmpty ? .green : .orange)
            if issues.isEmpty {
                Text("PlexBar’s catalog relationships, mock server data, and registered artwork passed validation.").foregroundStyle(.secondary)
                Text("Visual quality and source accuracy remain editorial decisions.").font(.caption).foregroundStyle(.secondary)
            } else {
                List(issues) { issue in
                    VStack(alignment: .leading, spacing: 4) { Text(issue.context).font(.headline); Text(issue.message).foregroundStyle(.secondary) }
                }.frame(height: 320)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 560)
    }
}
