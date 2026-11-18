import Darwin
import Foundation
import GeraniaCore

public actor ACPTransport: HermesTransport {
    public nonisolated let kind: TransportKind = .acp

    let config: HermesConfig
    var process: Process?
    var inputHandle: FileHandle?
    var connection: JSONRPCConnection?
    var stdoutTask: Task<Void, Never>?
    var stderrTask: Task<Void, Never>?
    var connectTask: Task<Void, any Error>?
    var initialized = false
    var cachedSession: SessionID?
    var activeTurn: ActiveTurn?
    var watchdogTask: Task<Void, Never>?
    var cancelled = false
    var pendingPermissions: [String: PendingPermission] = [:]

    struct ActiveTurn {
        let continuation: AsyncThrowingStream<HermesEvent, Error>.Continuation
        let session: SessionID
        var text: String
    }

    struct PermissionOption {
        let id: String
        let kind: String
    }

    struct PendingPermission {
        let rpcID: JSONValue
        let options: [PermissionOption]
    }

    public init(config: HermesConfig) {
        self.config = config
    }

    public func connect() async throws {
        if initialized, process?.isRunning == true {
            return
        }
        if let connectTask {
            try await connectTask.value
            return
        }
        let task = Task { try await self.establish() }
        connectTask = task
        do {
            try await task.value
            connectTask = nil
        } catch {
            connectTask = nil
            throw error
        }
    }

    public func listSessions(limit: Int) async throws -> [SessionSummary] {
        try await connect()
        let result = try await rpc(
            "session/list",
            params: ["cwd": .string(workingDirectory)],
            timeout: .seconds(30)
        )
        guard let rows = result["sessions"]?.arrayValue else { return [] }
        let formatter = ISO8601DateFormatter()
        return rows.prefix(limit).compactMap { row in
            guard let id = row["sessionId"]?.stringValue else { return nil }
            let title = row["title"]?.stringValue ?? ""
            return SessionSummary(
                id: id,
                title: title.isEmpty ? id : title,
                updatedAt: row["updatedAt"]?.stringValue.flatMap(formatter.date(from:)),
                source: "acp",
                cwd: row["cwd"]?.stringValue
            )
        }
    }

    public func newSession(title: String?) async throws -> SessionID {
        try await connect()
        let sid = try await createSession()
        cachedSession = sid
        return sid
    }

    public nonisolated func send(
        _ text: String,
        session: SessionID?,
        mode: PromptMode
    ) -> AsyncThrowingStream<HermesEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination else { return }
                Task { await self?.cancelCurrentTurn() }
            }
            Task {
                await self.performTurn(text, session: session, mode: mode, continuation: continuation)
            }
        }
    }

    public func interrupt(session: SessionID) async {
        cancelled = true
        try? await connection?.notify("session/cancel", params: ["sessionId": .string(session)])
    }

    public func respond(to request: ServerRequest, with answer: ServerRequestAnswer) async throws {
        guard let pending = pendingPermissions.removeValue(forKey: request.id) else {
            throw HermesError.protocolError("неизвестный запрос \(request.id)")
        }
        let outcome: JSONValue
        switch answer {
        case .cancel:
            outcome = ["outcome": "cancelled"]
        case let .approval(choice):
            guard let option = matchOption(choice, in: pending.options) else {
                throw HermesError.protocolError("вариант \(choice) не предложен агентом")
            }
            outcome = ["outcome": "selected", "optionId": .string(option.id)]
        case .clarify:
            guard let option = pending.options.first(where: { $0.kind.contains("reject") })
                ?? pending.options.first
            else {
                throw HermesError.protocolError("агент не предложил вариантов ответа")
            }
            outcome = ["outcome": "selected", "optionId": .string(option.id)]
        }
        try await connection?.respond(
            id: pending.rpcID,
            result: ["outcome": outcome]
        )
    }

    public func close() async {
        initialized = false
        cancelled = true
        stdoutTask?.cancel()
        stderrTask?.cancel()
        watchdogTask?.cancel()
        await connection?.failAll(.disconnected("transport closed"))
        connection = nil
        process?.terminate()
        process = nil
        inputHandle = nil
        cachedSession = nil
    }

    var workingDirectory: String {
        let path = config.expandedWorkdir
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
           isDirectory.boolValue
        {
            return path
        }
        return config.homeDirectory
    }

    func rpc(
        _ method: String,
        params: JSONValue,
        timeout: Duration
    ) async throws -> JSONValue {
        guard let connection else {
            throw HermesError.connectionFailed("ACP is not connected")
        }
        return try await connection.call(method, params: params, timeout: timeout)
    }

    func writeFrame(_ frame: JSONValue) async throws {
        guard let inputHandle, process?.isRunning == true else {
            throw HermesError.connectionFailed("ACP process is not running")
        }
        var data = try frame.data()
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }
}
