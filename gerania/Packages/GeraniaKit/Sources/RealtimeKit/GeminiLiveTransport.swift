import Foundation
import GeraniaCore

public actor GeminiLiveTransport {
    public let configuration: LiveSessionConfiguration

    private var urlSession: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var eventsContinuation: AsyncStream<LiveEvent>.Continuation?
    private var setupContinuation: CheckedContinuation<Void, Error>?
    private var setupCompleted = false
    private var closed = false
    private var sendErrorReported = false
    private var lastResumptionHandle: String?

    public init(configuration: LiveSessionConfiguration) {
        self.configuration = configuration
    }

    public var isConnected: Bool {
        setupCompleted && !closed
    }

    public var resumptionHandle: String? {
        lastResumptionHandle
    }

    public func events() -> AsyncStream<LiveEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveEvent.self)
        eventsContinuation = continuation
        return stream
    }

    public func connect() async throws {
        guard !closed else {
            throw LiveError.sessionClosed("соединение уже закрыто")
        }
        guard !setupCompleted else {
            return
        }
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiveError.missingAPIKey
        }
        guard var components = URLComponents(string: configuration.endpoint) else {
            throw LiveError.invalidEndpoint
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "key", value: configuration.apiKey),
        ]
        guard let url = components.url else {
            throw LiveError.invalidEndpoint
        }

        Log.voice.notice("live: connecting to Gemini Live")

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: sessionConfiguration)
        let task = session.webSocketTask(with: url)
        urlSession = session
        socket = task
        task.resume()

        startReceiveLoop(task)
        startPingLoop(task)

        do {
            try await send(LiveWire.setup(configuration))
            try await waitForSetup()
            Log.voice.notice("live: setup complete")
        } catch {
            await close(reason: error.localizedDescription)
            throw error
        }
    }

    public func sendAudio(_ pcm: Data) async {
        guard setupCompleted, !closed, !pcm.isEmpty else {
            return
        }
        do {
            try await send(LiveWire.audio(pcm))
            sendErrorReported = false
        } catch {
            if !sendErrorReported {
                sendErrorReported = true
                emit(.error(.network(error.localizedDescription)))
            }
        }
    }

    public func sendText(_ text: String) async throws {
        guard setupCompleted, !closed else {
            throw LiveError.sessionClosed("сессия не готова")
        }
        try await send(LiveWire.text(text))
    }

    public func sendToolResponse(
        callID: String,
        name: String,
        response: JSONValue,
        scheduling: LiveToolScheduling? = .whenIdle
    ) async throws {
        guard setupCompleted, !closed else {
            throw LiveError.sessionClosed("сессия не готова")
        }
        try await send(LiveWire.toolResponse(
            callID: callID,
            name: name,
            response: response,
            scheduling: scheduling
        ))
    }

    public func close(reason: String? = nil) async {
        guard !closed else {
            return
        }
        closed = true
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        socket?.cancel(with: .normalClosure, reason: reason?.data(using: .utf8))
        socket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        setupContinuation?.resume(throwing: LiveError.cancelled)
        setupContinuation = nil
        eventsContinuation?.yield(.closed(reason: reason))
        eventsContinuation?.finish()
        eventsContinuation = nil
        Log.voice.notice("live: closed")
    }
}

extension GeminiLiveTransport {
    private func waitForSetup() async throws {
        if setupCompleted {
            return
        }
        let timeout = configuration.setupTimeout
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                self.installSetupWaiter(continuation)
            }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                self.setupTimedOut()
            }
        }
    }

    private func installSetupWaiter(_ continuation: CheckedContinuation<Void, Error>) {
        if setupCompleted {
            continuation.resume()
            return
        }
        setupContinuation = continuation
    }

    private func setupTimedOut() {
        guard let continuation = setupContinuation else {
            return
        }
        setupContinuation = nil
        continuation.resume(throwing: LiveError.timeout)
    }

    private func send(_ frame: JSONValue) async throws {
        guard let socket else {
            throw LiveError.sessionClosed("сокет не открыт")
        }
        let data = try frame.data()
        guard let text = String(data: data, encoding: .utf8) else {
            throw LiveError.protocolError("не удалось закодировать кадр")
        }
        try await socket.send(.string(text))
    }

    private func startReceiveLoop(_ task: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    await self?.handle(message)
                } catch {
                    await self?.handleDisconnect(error)
                    return
                }
            }
        }
    }

    private func startPingLoop(_ task: URLSessionWebSocketTask) {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self else {
                    return
                }
                task.sendPing { error in
                    guard let error else {
                        return
                    }
                    Task {
                        await self.handlePingFailure(error)
                    }
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard !closed else {
            return
        }
        let data: Data? = switch message {
        case let .data(value):
            value
        case let .string(value):
            value.data(using: .utf8)
        @unknown default:
            nil
        }
        guard let data, let frame = try? JSONValue(from: data) else {
            emit(.error(.protocolError("не удалось разобрать кадр")))
            return
        }
        for event in LiveWire.events(from: frame) {
            if case .setupComplete = event {
                setupCompleted = true
                setupContinuation?.resume()
                setupContinuation = nil
            }
            if case let .error(error) = event, !setupCompleted {
                setupContinuation?.resume(throwing: error)
                setupContinuation = nil
            }
            if case let .resumptionUpdate(handle, _) = event, !handle.isEmpty {
                lastResumptionHandle = handle
            }
            emit(event)
        }
    }

    private func handleDisconnect(_ error: Error) async {
        guard !closed else {
            return
        }
        closed = true
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        socket = nil

        let mapped = map(error)
        setupContinuation?.resume(throwing: mapped)
        setupContinuation = nil
        emit(.error(mapped))
        emit(.closed(reason: mapped.localizedDescription))
    }

    private func handlePingFailure(_ error: Error) {
        guard !closed, !sendErrorReported else {
            return
        }
        sendErrorReported = true
        emit(.error(.network(error.localizedDescription)))
    }

    private func map(_ error: Error) -> LiveError {
        if let urlError = error as? URLError {
            return switch urlError.code {
            case .userAuthenticationRequired, .userCancelledAuthentication:
                .unauthorized
            case .timedOut:
                .timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
                .network(urlError.localizedDescription)
            default:
                .network(urlError.localizedDescription)
            }
        }
        return .network(error.localizedDescription)
    }

    private func emit(_ event: LiveEvent) {
        eventsContinuation?.yield(event)
    }
}
