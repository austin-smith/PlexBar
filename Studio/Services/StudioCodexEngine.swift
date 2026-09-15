import Foundation
import Observation

@Observable @MainActor
final class StudioCodexEngine {

    var activity = ""
    var transcript = ""
    var approvals: [StudioCodexApproval] = []
    private(set) var isRunning = false
    @ObservationIgnored private var connection: StudioCodexConnection?
    @ObservationIgnored private var completion: CheckedContinuation<StudioCodexResult, Error>?
    @ObservationIgnored private var outcome: Result<StudioCodexResult, Error>?
    @ObservationIgnored private var result = StudioCodexResult(threadID: "", model: "", text: "", images: [])
    @ObservationIgnored private var activeTurnID: String?

    func run(executable: String, directory: URL, prompt: String, references: [URL] = [], threadID: String? = nil,
             schema: StudioJSON? = nil, requiresImages: Bool = false,
             didStart: @escaping (String, String) throws -> Void) async throws -> StudioCodexResult {
        guard !isRunning else { throw StudioError.invalid("A Codex job is already running.") }
        isRunning = true
        activity = "Connecting to Codex…"
        transcript = ""
        approvals = []
        outcome = nil
        activeTurnID = nil
        result = .init(threadID: "", model: "", text: "", images: [])
        let rpc = StudioCodexConnection()
        connection = rpc
        rpc.onNotification = { [weak self] method, payload in self?.receive(method, payload) }
        rpc.onRequest = { [weak self, weak rpc] id, method, payload in
            guard let self, let rpc else { return }
            if ["item/commandExecution/requestApproval", "item/fileChange/requestApproval"].contains(method) {
                self.approvals.append(.init(rpcID: id, method: method, details: payload.prettyPrinted))
            } else {
                do { try rpc.rejectUnsupported(id: id, method: method) }
                catch { self.finish(.failure(error)) }
                self.append("Codex requested unsupported interaction: \(method)")
            }
        }
        rpc.onExit = { [weak self] error in self?.finish(.failure(error)) }
        defer {
            rpc.onExit = nil
            rpc.stop()
            connection = nil
            approvals = []
            isRunning = false
        }
        return try await withTaskCancellationHandler {
            try await rpc.start(executable: executable, cwd: directory)
            let account = try await rpc.request("account/read")
            guard account["account"]?["type"]?.string == "chatgpt" else {
                throw StudioError.invalid("Use your normal Codex account to continue. Sign in to Codex with ChatGPT, then reconnect Studio.")
            }
            let capabilities = try await rpc.request("modelProvider/capabilities/read")
            if requiresImages, capabilities["imageGeneration"] != .bool(true) {
                throw StudioError.invalid("This Codex installation does not expose built-in image generation.")
            }
            var params: [String: StudioJSON] = [
                "cwd": .string(directory.path), "approvalPolicy": .string("on-request"),
                "sandbox": .string("workspace-write"), "modelProvider": .string("openai")
            ]
            if let threadID { params["threadId"] = .string(threadID) }
            let opened = try await rpc.request(threadID == nil ? "thread/start" : "thread/resume", .object(params))
            guard let openedID = opened["thread"]?["id"]?.string else { throw StudioError.invalid("Codex returned no conversation ID.") }
            result.threadID = openedID
            result.model = opened["model"]?.string ?? "Codex configured model"
            try didStart(openedID, result.model)
            try Task.checkCancellation()
            var input: [StudioJSON] = [.object(["type": .string("text"), "text": .string(prompt)])]
            input += references.map { .object(["type": .string("localImage"), "path": .string($0.path)]) }
            var turn: [String: StudioJSON] = [
                "threadId": .string(openedID), "input": .array(input),
                "sandboxPolicy": .object(["type": .string("workspaceWrite"), "writableRoots": .strings([directory.path]), "networkAccess": .bool(false)]),
                "approvalPolicy": .string("on-request")
            ]
            if let schema { turn["outputSchema"] = schema }
            activity = requiresImages ? "Codex is creating artwork…" : "Codex is researching the catalog…"
            let started = try await rpc.request("turn/start", .object(turn))
            activeTurnID = started["turn"]?["id"]?.string
            try Task.checkCancellation()
            if let outcome { return try outcome.get() }
            return try await withCheckedThrowingContinuation { completion = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in await self?.cancel() }
        }
    }

    func answer(_ approval: StudioCodexApproval, allow: Bool) {
        do {
            try connection?.respond(id: approval.rpcID, result: .object(["decision": .string(allow ? "accept" : "decline")]))
            approvals.removeAll { $0.id == approval.id }
        } catch { finish(.failure(error)) }
    }

    func cancel() async {
        if let activeTurnID, let connection {
            _ = try? await connection.request("turn/interrupt", .object(["threadId": .string(result.threadID), "turnId": .string(activeTurnID)]), timeout: .seconds(3))
        }
        finish(.failure(CancellationError()))
        connection?.stop()
    }

    private func receive(_ method: String, _ payload: StudioJSON) {
        if method.hasPrefix("item/") || method.hasPrefix("turn/") {
            guard !result.threadID.isEmpty, payload["threadId"]?.string == result.threadID else { return }
        }
        switch method {
        case "item/agentMessage/delta":
            if let delta = payload["delta"]?.string { transcript = String((transcript + delta).suffix(64_000)) }
        case "item/started":
            if let type = payload["item"]?["type"]?.string {
                activity = type == "imageGeneration" ? "Generating image…" : type == "webSearch" ? "Checking sources…" : "Codex is working…"
            }
        case "item/completed":
            guard let item = payload["item"] else { return }
            if item["type"]?.string == "imageGeneration" { result.images.append(item) }
            if item["type"]?.string == "agentMessage", item["phase"]?.string != "commentary", let text = item["text"]?.string {
                result.text = text
            }
        case "turn/started": activeTurnID = payload["turn"]?["id"]?.string
        case "turn/completed":
            let turn = payload["turn"]
            switch turn?["status"]?.string {
            case "completed": finish(.success(result))
            case "interrupted": finish(.failure(CancellationError()))
            default: finish(.failure(StudioError.invalid(turn?["error"]?["message"]?.string ?? "Codex could not complete this job.")))
            }
        case "error": append(payload["message"]?.string ?? payload.prettyPrinted)
        default: break
        }
    }

    private func append(_ text: String) { transcript = String((transcript + "\n" + text + "\n").suffix(64_000)) }
    private func finish(_ value: Result<StudioCodexResult, Error>) {
        guard outcome == nil else { return }
        outcome = value
        completion?.resume(with: value)
        completion = nil
    }
}
