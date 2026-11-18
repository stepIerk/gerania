import Darwin
import Foundation
import GeraniaCore

extension ACPTransport {
    func processUpdate(_ params: JSONValue) async {
        guard let activeTurn,
              params["sessionId"]?.stringValue == activeTurn.session
        else { return }
        for event in HermesEventMapper.acpUpdate(params) {
            switch event {
            case let .textDelta(text):
                self.activeTurn?.text += text
                self.activeTurn?.continuation.yield(event)
            case let .failed(error):
                finishTurn(with: .failed(error))
            default:
                self.activeTurn?.continuation.yield(event)
            }
        }
    }

    func performTurn(
        _ text: String,
        session: SessionID?,
        mode: PromptMode,
        continuation: AsyncThrowingStream<HermesEvent, Error>.Continuation
    ) async {
        if activeTurn != nil {
            await cancelCurrentTurn()
            finishTurn(with: .cancelled)
        }
        do {
            try await connect()
            let sid = try await resolveSession(session)
            cancelled = false
            activeTurn = ActiveTurn(continuation: continuation, session: sid, text: "")
            continuation.yield(.sessionBound(sid))
            startWatchdog(session: sid)
            let result = try await rpc(
                "session/prompt",
                params: [
                    "sessionId": .string(sid),
                    "prompt": [["type": "text", "text": .string(config.prompt(for: text, mode: mode))]],
                ],
                timeout: .seconds(900)
            )
            watchdogTask?.cancel()
            let stopReason = result["stopReason"]?.stringValue
            let finalText = activeTurn?.text
            if cancelled || stopReason == "cancelled" {
                finishTurn(with: .cancelled)
            } else if stopReason == "refusal" {
                finishTurn(with: .failed(.protocolError("Hermes отказался отвечать")))
            } else {
                finishTurn(with: .completed(finalText: finalText))
            }
        } catch {
            finishTurn(with: .failed(error as? HermesError ?? .protocolError(error.localizedDescription)))
        }
    }

    func resolveSession(_ requested: SessionID?) async throws -> SessionID {
        if let requested, !requested.isEmpty {
            if requested != cachedSession {
                do {
                    _ = try await rpc(
                        "session/load",
                        params: [
                            "sessionId": .string(requested),
                            "cwd": .string(workingDirectory),
                            "mcpServers": [],
                        ],
                        timeout: .seconds(60)
                    )
                    cachedSession = requested
                } catch {
                    let sid = try await createSession()
                    cachedSession = sid
                    return sid
                }
            }
            return requested
        }
        if let cachedSession {
            return cachedSession
        }
        let sid = try await createSession()
        cachedSession = sid
        return sid
    }

    func createSession() async throws -> SessionID {
        let result = try await rpc(
            "session/new",
            params: [
                "cwd": .string(workingDirectory),
                "mcpServers": [],
            ],
            timeout: .seconds(60)
        )
        guard let sid = result["sessionId"]?.stringValue else {
            throw HermesError.protocolError("session/new returned no sessionId")
        }
        return sid
    }

    func startWatchdog(session: SessionID) {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(900))
            guard let self else { return }
            await self.interrupt(session: session)
            await self.failTimedOutTurn()
        }
    }

    func failTimedOutTurn() {
        finishTurn(with: .failed(.timeout("ответ Hermes")))
    }

    func cancelCurrentTurn() async {
        guard let sid = activeTurn?.session else { return }
        await interrupt(session: sid)
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
}
