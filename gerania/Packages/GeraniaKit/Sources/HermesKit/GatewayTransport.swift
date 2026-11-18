import Foundation
import GeraniaCore

public actor GatewayTransport: HermesTransport {
    public nonisolated let kind: TransportKind = .gateway

    /// The gateway can rename a session through `session.mutate`.
    public nonisolated var supportsRenaming: Bool {
        true
    }

    public nonisolated func renameSession(id: SessionID, title: String) async throws {
        try await renameThroughGateway(id: id, title: title)
    }

    static let protocolName = "hermes-gateway-v1"
    static let ticketPrefix = "hermes-gateway-ticket."

    let config: HermesConfig
    let session: URLSession
    var socket: URLSessionWebSocketTask?
    var connection: JSONRPCConnection?
    var receiveTask: Task<Void, Never>?
    var keepaliveTask: Task<Void, Never>?
    var watchdogTask: Task<Void, Never>?
    var connectTask: Task<Void, any Error>?
    var connected = false
    var cachedSession: SessionID?
    var generation: Int?
    var activeTurn: ActiveTurn?
    var pendingRequests: [String: JSONValue] = [:]

    struct ActiveTurn {
        let continuation: AsyncThrowingStream<HermesEvent, Error>.Continuation
        let session: SessionID
        let submissionID: String
        var text: String
    }

    public init(config: HermesConfig) {
        self.config = config
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    public func connect() async throws {
        if connected {
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
            "session.list",
            params: ["scope": "stored", "limit": JSONValue.int(Int64(limit))],
            timeout: .seconds(30)
        )
        guard let rows = result["sessions"]?.arrayValue else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"]?.stringValue else { return nil }
            let started = Date(timeIntervalSince1970: row["started_at"]?.doubleValue ?? 0)
            let updated = row["last_activity_at"]?.doubleValue.map(Date.init(timeIntervalSince1970:))
            let preview = row["preview"]?.stringValue ?? ""
            let title = row["title"]?.stringValue ?? ""
            return SessionSummary(
                id: id,
                title: title.isEmpty ? preview : title,
                preview: preview,
                updatedAt: updated ?? (started.timeIntervalSince1970 > 0 ? started : nil),
                source: row["source"]?.stringValue ?? "",
                cwd: row["cwd"]?.stringValue,
                startedAt: started.timeIntervalSince1970 > 0 ? started : nil,
                messageCount: row["message_count"]?.intValue ?? 0,
                isRunning: row["running"]?.boolValue ?? false
            )
        }
    }

    public func newSession(title: String?) async throws -> SessionID {
        try await connect()
        return try await createSession(title: title)
    }

    public nonisolated func send(
        _ text: String,
        session: SessionID?,
        mode: PromptMode
    ) -> AsyncThrowingStream<HermesEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination else { return }
                Task { await self?.turnWasCancelled() }
            }
            Task {
                await self.performTurn(text, session: session, mode: mode, continuation: continuation)
            }
        }
    }

    public func interrupt(session: SessionID) async {
        guard let generation else { return }
        _ = try? await rpc(
            "session.interrupt",
            params: [
                "session_id": .string(session),
                "execution_generation": JSONValue.int(Int64(generation)),
            ],
            timeout: .seconds(30)
        )
    }

    public func respond(to request: ServerRequest, with answer: ServerRequestAnswer) async throws {
        if let rpcID = pendingRequests.removeValue(forKey: request.id) {
            let result: JSONValue = switch answer {
            case let .approval(choice):
                ["choice": .string(choice)]
            case let .clarify(text):
                ["answer": .string(text)]
            case .cancel:
                request.kind == .clarify ? ["answer": ""] : ["choice": "deny"]
            }
            try await connection?.respond(id: rpcID, result: result)
            return
        }

        let sid = request.sessionID ?? cachedSession ?? ""
        let generation = request.executionGeneration ?? self.generation ?? 0
        switch request.kind {
        case .approval:
            let choice: String = switch answer {
            case let .approval(value): value
            case .clarify: "deny"
            case .cancel: "deny"
            }
            _ = try await rpc(
                "approval.respond",
                params: [
                    "session_id": .string(sid),
                    "execution_generation": JSONValue.int(Int64(generation)),
                    "prompt_id": .string(request.id),
                    "choice": .string(choice),
                ],
                timeout: .seconds(30)
            )
        case .clarify:
            let value: String = switch answer {
            case let .clarify(text): text
            case let .approval(choice): choice
            case .cancel: ""
            }
            _ = try await rpc(
                "clarify.respond",
                params: [
                    "session_id": .string(sid),
                    "execution_generation": JSONValue.int(Int64(generation)),
                    "prompt_id": .string(request.id),
                    "answer": .string(value),
                ],
                timeout: .seconds(30)
            )
        case .other:
            throw HermesError.protocolError("неизвестный запрос \(request.id)")
        }
    }

    public func close() async {
        connected = false
        receiveTask?.cancel()
        keepaliveTask?.cancel()
        watchdogTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        await connection?.failAll(.disconnected("transport closed"))
        connection = nil
    }
}
