import Foundation
import GeraniaCore

extension GatewayTransport {
    func performTurn(
        _ text: String,
        session: SessionID?,
        mode: PromptMode,
        continuation: AsyncThrowingStream<HermesEvent, Error>.Continuation
    ) async {
        if activeTurn != nil {
            finishTurn(with: .cancelled)
        }
        do {
            try await connect()
            let sid = try await resolveSession(session)
            let submissionID = UUID().uuidString.lowercased()
            generation = nil
            activeTurn = ActiveTurn(
                continuation: continuation,
                session: sid,
                submissionID: submissionID,
                text: ""
            )
            continuation.yield(.sessionBound(sid))
            let prompt = config.prompt(for: text, mode: mode)
            do {
                try await submit(prompt, session: sid, submissionID: submissionID)
            } catch let error as JSONRPCError where isBusy(error) {
                await interrupt(session: sid)
                try await Task.sleep(for: .milliseconds(300))
                try await submit(prompt, session: sid, submissionID: submissionID)
            }
            startWatchdog(submissionID: submissionID)
        } catch {
            finishTurn(with: .failed(Self.hermesError(error)))
        }
    }

    func submit(_ text: String, session: SessionID, submissionID: String) async throws {
        _ = try await rpc(
            "prompt.submit",
            params: [
                "session_id": .string(session),
                "text": .string(text),
                "submission_id": .string(submissionID),
            ],
            timeout: .seconds(30)
        )
    }

    func resolveSession(_ requested: SessionID?) async throws -> SessionID {
        if let requested, !requested.isEmpty {
            cachedSession = requested
            return requested
        }
        if let cachedSession {
            return cachedSession
        }
        return try await createSession(title: nil)
    }

    /// Renames the session through the official `session.mutate` method.
    func renameThroughGateway(id: SessionID, title: String) async throws {
        _ = try await rpc(
            "session.mutate",
            params: [
                "session_id": .string(id),
                "operation": "rename",
                "payload": ["title": .string(title)],
            ],
            timeout: .seconds(30)
        )
    }

    func createSession(title: String?) async throws -> SessionID {
        let resolvedTitle = title ?? "\(config.sessionTitlePrefix)-\(Int(Date().timeIntervalSince1970))"
        var params: [String: JSONValue] = [
            "request_id": .string(UUID().uuidString.lowercased()),
            "source": "gui",
            "cwd": .string(config.expandedWorkdir),
            "title": .string(resolvedTitle),
        ]
        if !config.model.isEmpty {
            params["model"] = .string(config.model)
        }
        if !config.provider.isEmpty {
            params["provider"] = .string(config.provider)
        }
        let result = try await rpc("session.create", params: .object(params), timeout: .seconds(60))
        guard let sid = result["session_id"]?.stringValue else {
            throw HermesError.protocolError("session.create returned no session_id")
        }
        cachedSession = sid
        return sid
    }

    func startWatchdog(submissionID: String) {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard let self else { return }
            await self.turnTimedOut(submissionID: submissionID)
        }
    }

    func turnTimedOut(submissionID: String) {
        guard activeTurn?.submissionID == submissionID else { return }
        if let session = activeTurn?.session {
            Task { await self.interrupt(session: session) }
        }
        finishTurn(with: .failed(.timeout("ответ Hermes")))
    }

    func turnWasCancelled() async {
        guard let sid = activeTurn?.session else { return }
        await interrupt(session: sid)
    }

    func processEvent(_ params: JSONValue) async {
        guard let type = params["type"]?.stringValue, type != "gateway.ready" else { return }
        if type == "message.start" {
            generation = params["execution_generation"]?.intValue
        }
        let eventSession = params["session_id"]?.stringValue
        if let eventSession, let activeTurn, eventSession != activeTurn.session, type != "approval.request",
           type != "clarify.request"
        {
            return
        }
        for event in HermesEventMapper.gatewayEvent(params) {
            switch event {
            case let .textDelta(text):
                if activeTurn != nil {
                    activeTurn?.text += text
                }
                activeTurn?.continuation.yield(event)
            case .completed:
                finishTurn(with: event)
            case .cancelled:
                finishTurn(with: .cancelled)
            case let .failed(error):
                finishTurn(with: .failed(error))
            default:
                activeTurn?.continuation.yield(event)
            }
        }
    }

    func finishTurn(with event: HermesEvent?) {
        guard let turn = activeTurn else { return }
        activeTurn = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        if let event {
            turn.continuation.yield(event)
        }
        turn.continuation.finish()
    }

    func handleServerRequest(_ request: JSONRPCRequest) -> JSONRPCDecision {
        guard let serverRequest = HermesEventMapper.gatewayServerRequest(
            id: request.id,
            method: request.method,
            params: request.params
        ) else {
            return .error(code: -32601, message: "Method not found: \(request.method)")
        }
        pendingRequests[serverRequest.id] = request.id
        activeTurn?.continuation.yield(.serverRequest(serverRequest))
        return .deferred
    }
}
