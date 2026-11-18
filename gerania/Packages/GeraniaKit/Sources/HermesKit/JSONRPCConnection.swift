import Foundation
import GeraniaCore

public struct JSONRPCRequest: Sendable, Equatable {
    public let id: JSONValue
    public let method: String
    public let params: JSONValue

    public init(id: JSONValue, method: String, params: JSONValue) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public enum JSONRPCDecision: Sendable, Equatable {
    case result(JSONValue)
    case error(code: Int, message: String)
    case deferred
}

public struct JSONRPCError: Error, LocalizedError, Sendable, Equatable {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public var errorDescription: String? {
        "JSON-RPC \(code): \(message)"
    }

    public static func timeout(_ operation: String) -> JSONRPCError {
        JSONRPCError(code: -32000, message: "timeout: \(operation)")
    }

    public static func disconnected(_ reason: String) -> JSONRPCError {
        JSONRPCError(code: -32001, message: "disconnected: \(reason)")
    }
}

public actor JSONRPCConnection {
    public typealias FrameSender = @Sendable (JSONValue) async throws -> Void
    public typealias RequestHandler = @Sendable (JSONRPCRequest) async -> JSONRPCDecision
    public typealias NotificationHandler = @Sendable (JSONRPCRequest) async -> Void

    private let sendFrame: FrameSender
    private var requestHandler: RequestHandler?
    private var notificationHandler: NotificationHandler?
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]

    public init(send: @escaping FrameSender) {
        sendFrame = send
    }

    public func setHandlers(
        request: RequestHandler?,
        notification: NotificationHandler?
    ) {
        requestHandler = request
        notificationHandler = notification
    }

    public func call(
        _ method: String,
        params: JSONValue = .object([:]),
        timeout: Duration = .seconds(60)
    ) async throws -> JSONValue {
        let id = nextID
        nextID += 1

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                await self?.timeOut(id: id, method: method)
            }
            timeouts[id] = timeoutTask
            let frame: JSONValue = [
                "jsonrpc": "2.0",
                "id": JSONValue.int(Int64(id)),
                "method": .string(method),
                "params": params,
            ]
            Task { [weak self] in
                do {
                    try await self?.sendFrame(frame)
                } catch {
                    await self?.failPending(
                        id: id,
                        error: .disconnected(error.localizedDescription)
                    )
                }
            }
        }
    }

    public func notify(_ method: String, params: JSONValue = .object([:])) async throws {
        try await sendFrame([
            "jsonrpc": "2.0",
            "method": .string(method),
            "params": params,
        ])
    }

    public func respond(id: JSONValue, result: JSONValue) async throws {
        try await sendFrame(["jsonrpc": "2.0", "id": id, "result": result])
    }

    public func respondError(id: JSONValue, code: Int, message: String) async throws {
        try await sendFrame([
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": JSONValue.int(Int64(code)), "message": .string(message)],
        ])
    }

    public func handle(_ frame: JSONValue) async {
        guard let object = frame.objectValue else { return }
        if let method = object["method"]?.stringValue {
            let request = JSONRPCRequest(
                id: object["id"] ?? .null,
                method: method,
                params: object["params"] ?? .object([:])
            )
            if object["id"] != nil, object["id"] != .null {
                await handleRequest(request)
            } else {
                await notificationHandler?(request)
            }
            return
        }

        guard let idValue = object["id"], let id = idValue.intValue,
              let continuation = pending.removeValue(forKey: id) else { return }
        timeouts.removeValue(forKey: id)?.cancel()

        if let error = object["error"]?.objectValue {
            continuation.resume(throwing: JSONRPCError(
                code: error["code"]?.intValue ?? -32603,
                message: error["message"]?.stringValue ?? "unknown error",
                data: error["data"]
            ))
        } else {
            continuation.resume(returning: object["result"] ?? .null)
        }
    }

    public func failAll(_ error: JSONRPCError) {
        for task in timeouts.values {
            task.cancel()
        }
        timeouts.removeAll()
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async {
        guard let requestHandler else {
            try? await respondError(
                id: request.id,
                code: -32601,
                message: "Method not found: \(request.method)"
            )
            return
        }
        switch await requestHandler(request) {
        case let .result(result):
            try? await respond(id: request.id, result: result)
        case let .error(code, message):
            try? await respondError(id: request.id, code: code, message: message)
        case .deferred:
            break
        }
    }

    private func timeOut(id: Int, method: String) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        timeouts.removeValue(forKey: id)?.cancel()
        continuation.resume(throwing: JSONRPCError.timeout(method))
    }

    private func failPending(id: Int, error: JSONRPCError) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        timeouts.removeValue(forKey: id)?.cancel()
        continuation.resume(throwing: error)
    }
}
