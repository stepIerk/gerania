import Darwin
import Foundation
import GeraniaCore

extension ACPTransport {
    func establish() async throws {
        if initialized, process?.isRunning == true {
            return
        }
        let binary = try config.hermesBinary()
        let process = Process()
        process.executableURL = binary
        process.arguments = ["acp"]
        process.environment = config.processEnvironment()
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        let inputHandle = input.fileHandleForWriting
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw HermesError.processFailed(
                exitCode: -1,
                message: error.localizedDescription
            )
        }
        signal(SIGPIPE, SIG_IGN)
        self.process = process
        self.inputHandle = inputHandle

        let conn = JSONRPCConnection(send: { [weak self] frame in
            guard let self else { throw HermesError.connectionFailed("transport released") }
            try await self.writeFrame(frame)
        })
        await conn.setHandlers(
            request: { [weak self] request in
                await self?.handleServerRequest(request)
                    ?? .error(code: -32601, message: "Method not found: \(request.method)")
            },
            notification: { [weak self] notification in
                await self?.handleNotification(notification)
            }
        )
        connection = conn
        startReaders(output: output, errors: errors)
        _ = try await rpc(
            "initialize",
            params: [
                "protocolVersion": 1,
                "clientCapabilities": [:],
                "clientInfo": ["name": "Gerania", "version": .string(HermesKitInfo.version)],
            ],
            timeout: .seconds(30)
        )
        initialized = true
    }

    func startReaders(output: Pipe, errors: Pipe) {
        stdoutTask?.cancel()
        stdoutTask = Task { [weak self] in
            await self?.readStdout(output.fileHandleForReading)
        }
        stderrTask?.cancel()
        stderrTask = Task {
            for await data in FileHandleChunks.stream(errors.fileHandleForReading) {
                let text = String(data: data, encoding: .utf8) ?? ""
                Log.hermes.debug("acp: \(text, privacy: .public)")
            }
        }
    }

    func readStdout(_ handle: FileHandle) async {
        var buffer = Data()
        for await chunk in FileHandleChunks.stream(handle) {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                await ingest(Data(line))
            }
        }
        await processExited("ACP process closed stdout")
    }

    func ingest(_ data: Data) async {
        guard !data.isEmpty, let frame = try? JSONValue(from: data) else { return }
        await connection?.handle(frame)
    }

    func processExited(_ reason: String) async {
        initialized = false
        process = nil
        inputHandle = nil
        await connection?.failAll(.disconnected(reason))
        if activeTurn != nil {
            finishTurn(with: .failed(.processFailed(exitCode: -1, message: reason)))
        }
    }

    func handleServerRequest(_ request: JSONRPCRequest) -> JSONRPCDecision {
        guard request.method == "session/request_permission",
              let serverRequest = HermesEventMapper.acpPermissionRequest(
                  id: request.id,
                  params: request.params
              )
        else {
            return .error(code: -32601, message: "Method not found: \(request.method)")
        }
        let options = request.params["options"]?.arrayValue?.compactMap { option -> PermissionOption? in
            guard let id = option["optionId"]?.stringValue else { return nil }
            return PermissionOption(
                id: id,
                kind: option["kind"]?.stringValue ?? option["name"]?.stringValue ?? ""
            )
        } ?? []
        pendingPermissions[serverRequest.id] = PendingPermission(
            rpcID: request.id,
            options: options
        )
        activeTurn?.continuation.yield(.serverRequest(serverRequest))
        return .deferred
    }

    func handleNotification(_ notification: JSONRPCRequest) async {
        guard notification.method == "session/update" else { return }
        await processUpdate(notification.params)
    }

    func matchOption(_ choice: String, in options: [PermissionOption]) -> PermissionOption? {
        if let exact = options.first(where: { $0.id == choice }) {
            return exact
        }
        let normalized = choice.lowercased()
        let kind: String = switch normalized {
        case "once", "allow_once", "allowonce": "allow_once"
        case "session", "always", "allow_always", "allowalways": "allow_always"
        case "deny", "reject", "reject_once": "reject_once"
        default: normalized
        }
        return options.first(where: { $0.kind == kind })
            ?? options.first(where: { $0.kind.contains("allow") })
    }
}
