import Foundation

/// Owns exactly one App Server process. Notifications never wait for an RPC response.
@MainActor
final class StudioCodexConnection {
    var onNotification: ((String, StudioJSON) -> Void)?
    var onRequest: ((StudioJSON, String, StudioJSON) -> Void)?
    var onExit: ((Error) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var reader: Task<Void, Never>?
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<StudioJSON, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var buffer = Data()
    private(set) var isRunning = false

    static var defaultExecutable: String {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin").split(separator: ":")
        return paths.map { String($0) + "/codex" }.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/codex"
    }

    @discardableResult
    func start(executable: String, cwd: URL) async throws -> StudioJSON {
        guard process == nil else { throw StudioError.invalid("Codex is already connected.") }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw StudioError.invalid("Codex executable not found at \(executable). Choose your installed Codex executable in the Codex panel.")
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = ["app-server"]
        child.currentDirectoryURL = cwd
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr
        try child.run()
        process = child
        input = stdin.fileHandleForWriting
        isRunning = true
        let chunks = AsyncStream<Data> { continuation in
            DispatchQueue(label: "PlexBar.Studio.Codex.stdout").async {
                while true {
                    let data = stdout.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    continuation.yield(data)
                }
                continuation.finish()
            }
        }
        // Drain stderr independently so diagnostics cannot block the protocol pipe.
        DispatchQueue(label: "PlexBar.Studio.Codex.stderr").async {
            while !stderr.fileHandleForReading.availableData.isEmpty { }
        }
        reader = Task { [weak self] in
            for await data in chunks {
                guard let self, !Task.isCancelled else { return }
                do { try self.receive(data) }
                catch { self.stop(error: error); return }
            }
            guard let self, self.isRunning else { return }
            self.stop(error: StudioError.invalid("Codex App Server closed its connection. The unfinished job is retained for review."))
        }
        do {
            let initialized = try await request("initialize", .object([
                "clientInfo": .object(["name": .string("plexbar_mock_studio"), "title": .string("PlexBar Mock Studio"), "version": .string("1.0")]),
                "capabilities": .object(["experimentalApi": .bool(true)])
            ]))
            try send(.object(["method": .string("initialized")]))
            return initialized
        } catch { stop(error: error); throw error }
    }

    func request(_ method: String, _ params: StudioJSON = .object([:]), timeout: Duration = .seconds(30)) async throws -> StudioJSON {
        guard isRunning else { throw StudioError.invalid("Codex is not connected.") }
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.finish(id, result: .failure(StudioError.invalid("Codex did not acknowledge \(method) in time.")))
                }
                do { try send(.object(["id": .integer(id), "method": .string(method), "params": params])) }
                catch { finish(id, result: .failure(error)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) }
        }
    }

    func respond(id: StudioJSON, result: StudioJSON) throws {
        try send(.object(["id": id, "result": result]))
    }

    func rejectUnsupported(id: StudioJSON, method: String) throws {
        try send(.object(["id": id, "error": .object(["code": .integer(-32601), "message": .string("Mock Studio does not support \(method).")])]))
    }

    private func send(_ value: StudioJSON) throws {
        guard isRunning, let input else { throw StudioError.invalid("Codex is not connected.") }
        // The wire is JSONL: pretty-printed JSON would split one message into many.
        var data = try JSONEncoder().encode(value)
        data.append(0x0a)
        try input.write(contentsOf: data)
    }

    /// Accepts arbitrary pipe chunks, including multiple messages and split UTF-8 scalars.
    func receive(_ data: Data) throws {
        buffer.append(data)
        guard buffer.count <= 100 * 1024 * 1024 else { throw StudioError.invalid("Codex sent a protocol message larger than 100 MB.") }
        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.isEmpty { continue }
            let message = try JSONDecoder().decode(StudioJSON.self, from: line)
            if let method = message["method"]?.string {
                if let id = message["id"] {
                    if let onRequest { onRequest(id, method, message["params"] ?? .object([:])) }
                    else { try rejectUnsupported(id: id, method: method) }
                } else { onNotification?(method, message["params"] ?? .object([:])) }
            } else if let id = message["id"]?.integer {
                if let error = message["error"] {
                    finish(id, result: .failure(StudioError.invalid(error["message"]?.string ?? "Codex request failed.")))
                } else if let result = message["result"] { finish(id, result: .success(result)) }
                else { throw StudioError.invalid("Codex returned an RPC response without a result or error.") }
            } else { throw StudioError.invalid("Codex returned an invalid RPC message.") }
        }
    }

    private func finish(_ id: Int, result: Result<StudioJSON, Error>) {
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    func stop(error: Error = CancellationError()) {
        let wasRunning = isRunning
        isRunning = false
        try? input?.close()
        input = nil
        let child = process
        process = nil
        if let child, child.isRunning {
            child.terminate()
            // Bound shutdown of the process we own; never kill by name or pattern.
            Task.detached {
                try? await Task.sleep(for: .seconds(3))
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        reader?.cancel()
        reader = nil
        buffer.removeAll()
        for id in Array(pending.keys) { finish(id, result: .failure(error)) }
        if wasRunning { onExit?(error) }
    }
}
