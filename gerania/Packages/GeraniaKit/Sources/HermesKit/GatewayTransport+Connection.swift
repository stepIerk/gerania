import Foundation
import GeraniaCore

extension GatewayTransport {
    func establish() async throws {
        if connected {
            return
        }
        let conn = JSONRPCConnection(send: { [weak self] frame in
            guard let self else { throw HermesError.connectionFailed("transport released") }
            try await self.sendFrame(frame)
        })
        await conn.setHandlers(
            request: { [weak self] request in
                await self?.handleServerRequest(request)
                    ?? .error(code: -32601, message: "Method not found: \(request.method)")
            },
            notification: nil
        )
        connection = conn
        try await openSocket()
        startReceiving()
        try await performHandshake()
        startKeepalive()
        connected = true
    }

    func openSocket() async throws {
        let endpoint = try await GatewayEndpoint.ensure(config)
        guard let url = endpoint.webSocketURL else {
            throw HermesError.protocolError("invalid gateway URL")
        }
        let ticket = try endpoint.mintTicket()
        var request = URLRequest(url: url)
        request.setValue(
            "\(Self.protocolName), \(Self.ticketPrefix)\(ticket)",
            forHTTPHeaderField: "Sec-WebSocket-Protocol"
        )
        let task = session.webSocketTask(with: request)
        socket = task
        task.resume()
        try await waitUntilReady(task)
    }

    func performHandshake() async throws {
        _ = try await rpc(
            "client.capabilities",
            params: ["server_requests": true],
            timeout: .seconds(15)
        )
        _ = try await rpc("runtime.describe", params: .object([:]), timeout: .seconds(15))
    }

    func waitUntilReady(_ task: URLSessionWebSocketTask) async throws {
        for _ in 0 ..< 20 {
            let text = try await Self.receiveText(task, timeout: .seconds(15))
            guard let data = text.data(using: .utf8) else { continue }
            let frame = try JSONValue(from: data)
            await connection?.handle(frame)
            let params = frame["params"] ?? .null
            if params["type"]?.stringValue == "gateway.ready" {
                return
            }
        }
        throw HermesError.timeout("gateway.ready")
    }

    func startReceiving() {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func receiveLoop() async {
        while !Task.isCancelled {
            guard let socket else { return }
            do {
                let text = try await Self.receiveText(socket, timeout: nil)
                guard let data = text.data(using: .utf8) else { continue }
                let frame = try JSONValue(from: data)
                await connection?.handle(frame)
                if frame["method"]?.stringValue == "event" {
                    await processEvent(frame["params"] ?? .null)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await connection?.failAll(.disconnected(error.localizedDescription))
                await reconnect()
                return
            }
        }
    }

    func reconnect() async {
        connected = false
        for attempt in 0 ..< 5 {
            let seconds = min(8.0, 0.5 * pow(2.0, Double(attempt)))
            try? await Task.sleep(for: .seconds(seconds))
            do {
                try await openSocket()
                startReceiving()
                try await performHandshake()
                connected = true
                return
            } catch {
                Log.hermes.debug("gateway reconnect failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        finishTurn(with: .failed(.connectionFailed("не удалось переподключиться")))
    }

    func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self else { return }
                if await !(self.isConnected) {
                    return
                }
                _ = try? await self.rpc("ping", params: .object([:]), timeout: .seconds(10))
            }
        }
    }

    var isConnected: Bool {
        connected
    }

    func rpc(
        _ method: String,
        params: JSONValue,
        timeout: Duration
    ) async throws -> JSONValue {
        guard let connection else {
            throw HermesError.connectionFailed("gateway is not connected")
        }
        return try await connection.call(method, params: params, timeout: timeout)
    }

    func sendFrame(_ frame: JSONValue) async throws {
        guard let socket else {
            throw HermesError.connectionFailed("gateway socket is closed")
        }
        let data = try frame.data()
        guard let text = String(data: data, encoding: .utf8) else {
            throw HermesError.protocolError("cannot encode a JSON frame")
        }
        try await socket.send(.string(text))
    }

    func isBusy(_ error: JSONRPCError) -> Bool {
        [4009, 4090, 4091].contains(error.code)
            || error.message.lowercased().contains("busy")
    }

    static func hermesError(_ error: any Error) -> HermesError {
        if let error = error as? HermesError {
            return error
        }
        if let error = error as? JSONRPCError {
            switch error.code {
            case -32000: return .timeout(error.message)
            case -32001: return .connectionFailed(error.message)
            default: return .protocolError(error.message)
            }
        }
        return .protocolError(error.localizedDescription)
    }

    static func receiveText(
        _ task: URLSessionWebSocketTask,
        timeout: Duration?
    ) async throws -> String {
        guard let timeout else {
            let message = try await task.receive()
            return try messageText(message)
        }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let message = try await task.receive()
                return try messageText(message)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw HermesError.timeout("gateway message")
            }
            guard let value = try await group.next() else {
                throw HermesError.timeout("gateway message")
            }
            group.cancelAll()
            return value
        }
    }

    static func messageText(
        _ message: URLSessionWebSocketTask.Message
    ) throws -> String {
        switch message {
        case let .string(text):
            return text
        case let .data(data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw HermesError.protocolError("gateway sent invalid UTF-8")
            }
            return text
        @unknown default:
            throw HermesError.protocolError("unknown WebSocket message")
        }
    }
}
