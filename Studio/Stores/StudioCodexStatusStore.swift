import Foundation
import Observation

@Observable @MainActor
final class StudioCodexStatusStore {
    enum Status { case checking, ready, needsAttention, unavailable }

    private(set) var status = Status.checking
    private(set) var message: String?
    private(set) var account: String?
    private(set) var version: String?

    func check(executable: String, directory: URL? = nil) async {
        guard !Task.isCancelled else { return }
        status = .checking
        message = nil
        account = nil
        version = nil
        let connection = StudioCodexConnection()
        defer { connection.stop() }
        do {
            try Task.checkCancellation()
            let initialized = try await connection.start(executable: executable, cwd: directory ?? StudioFiles.repositoryContentURL)
            try Task.checkCancellation()
            if let agent = initialized["userAgent"]?.string,
               let slash = agent.firstIndex(of: "/") {
                version = agent[agent.index(after: slash)...].split(whereSeparator: \.isWhitespace).first.map(String.init)
            }

            let response = try await connection.request("account/read")
            try Task.checkCancellation()
            guard response["account"]?["type"]?.string == "chatgpt" else {
                account = "Not signed in with ChatGPT"
                status = .needsAttention
                message = "Sign in to Codex with ChatGPT, then refresh."
                return
            }
            let email = response["account"]?["email"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            account = email.flatMap { $0.isEmpty ? nil : $0 } ?? "Signed in with ChatGPT"

            let capabilities = try await connection.request("modelProvider/capabilities/read")
            try Task.checkCancellation()
            guard capabilities["imageGeneration"] == .bool(true) else {
                status = .needsAttention
                message = "This Codex installation does not provide image generation."
                return
            }
            status = .ready
        } catch {
            guard !Task.isCancelled else { return }
            status = .unavailable
            message = error.localizedDescription
        }
    }
}
