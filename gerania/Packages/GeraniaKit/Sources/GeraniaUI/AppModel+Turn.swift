import Foundation
import GeraniaCore
import HermesKit

/// The part of the orchestrator that talks to Hermes.
extension AppModel {
    /// Sends a prompt to Hermes and streams the answer into the HUD.
    ///
    /// A new prompt interrupts the running one: there is only one active request.
    public func ask(_ text: String, mode: PromptMode = .text) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastPrompt = trimmed
        currentMode = mode
        settings.rememberPrompt(trimmed)
        cancelTurn()
        hud.reset()
        hud.showsModel = settings.showActiveModelInHUD
        hud.modelLabel = candidateModels.first?.model ?? settings.model
        dispatch(.turnStarted)
        turnTask = Task { [weak self] in
            await self?.runTurn(text: trimmed, mode: mode)
        }
    }

    /// Stops the running request.
    public func stop() {
        if isLiveActive {
            Task { await finishLive(reason: "Остановлено") }
            return
        }
        panels?.dismissDetail()
        cancelTurn()
        dispatch(.stop)
    }

    /// Answers an approval or clarification request.
    public func respond(to request: ServerRequest, with answer: ServerRequestAnswer) async {
        hud.approval = nil
        dispatch(.serverRequestAnswered)
        recordAnswerAudit(request, answer: answer)
        guard let transport else { return }
        do {
            try await transport.respond(to: request, with: answer)
        } catch {
            Log.hermes
                .error("cannot answer \(request.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Interrupts the running request without changing the state.
    func cancelTurn() {
        turnTask?.cancel()
        turnTask = nil
        guard let transport, let session = activeSessionID else { return }
        Task { await transport.interrupt(session: session) }
    }

    private func runTurn(text: String, mode: PromptMode) async {
        let candidates = await orderedCandidates()
        guard !candidates.isEmpty else {
            hud.errorDetails = "В настройках не выбрана ни одна модель."
            dispatch(.failed("Не выбрана модель — откройте Hermes → Модели"))
            turnTask = nil
            return
        }
        for (index, candidate) in candidates.enumerated() {
            let isLast = index == candidates.count - 1
            if Task.isCancelled {
                turnTask = nil
                return
            }
            do {
                let manager = try await makeTransport(candidate)
                let session = try await resolveSession(
                    text: text,
                    mode: mode,
                    manager: manager,
                    freshSession: index > 0
                )
                activeCandidate = candidate
                hud.modelLabel = candidate.model
                hud.showsModel = settings.showActiveModelInHUD
                var failure: HermesError?
                for try await event in manager.send(text, session: session, mode: mode) {
                    if case let .failed(error) = event {
                        failure = error
                        break
                    }
                    handle(event)
                }
                if let failure {
                    throw failure
                }
                await modelHealth.markHealthy(candidate)
                hud.flushStream()
                await chats.refresh()
                turnTask = nil
                return
            } catch is CancellationError {
                Log.hermes.debug("turn cancelled")
                turnTask = nil
                return
            } catch let error as HermesError {
                if let record = await modelHealth.markFailure(candidate, error: error), !isLast {
                    let issue = record.issue.rawValue
                    Log.hermes.info(
                        "model \(candidate.id, privacy: .public) → fallback (\(issue, privacy: .public))"
                    )
                    prepareFallback(to: candidates[index + 1])
                    continue
                }
                let message = friendlyMessage(for: error)
                hud.errorDetails = error.localizedDescription
                dispatch(.failed(message))
                turnTask = nil
                return
            } catch {
                Log.hermes.error("turn failed: \(error.localizedDescription, privacy: .public)")
                hud.errorDetails = error.localizedDescription
                dispatch(.failed(error.localizedDescription))
                turnTask = nil
                return
            }
        }
        turnTask = nil
    }

    func handle(_ event: HermesEvent) {
        switch event {
        case let .sessionBound(id):
            activeSessionID = id
            settings.lastSessionID = id
        case .thinkingStarted:
            break
        case let .reasoningDelta(text):
            hud.appendReasoning(text)
            dispatch(.reasoningDelta(text))
        case let .textDelta(text):
            hud.appendDelta(text)
            if shouldSpeak {
                speaker?.feed(text)
            }
            dispatch(.textDelta(text))
        case let .toolStarted(id, name, detail):
            let chip = ToolChip(id: id, name: name, detail: detail)
            hud.startTool(chip)
            if chip.isComputerUse {
                startComputerUseWatch()
            }
            dispatch(.toolStarted(chip))
        case let .toolOutput(id, imagePath, summary):
            hud.attachOutput(id: id, imagePath: imagePath, summary: summary)
            dispatch(.toolOutput(id: id, imagePath: imagePath, summary: summary))
        case let .toolFinished(id, ok):
            let chip = hud.tools.first { $0.id == id }
            hud.finishTool(id: id, ok: ok)
            if !hud.isComputerUseActive {
                stopComputerUseWatch()
            }
            dispatch(.toolFinished(id: id, ok: ok))
            if let chip {
                recordToolAudit(chip, ok: ok)
            }
        case let .serverRequest(request):
            hud.approval = request
            handleApprovalRequest(request)
            dispatch(.serverRequest(request))
        case let .completed(text):
            hud.flushStream()
            speaker?.finish()
            dispatch(.completed(finalText: text))
        case .cancelled:
            dispatch(.cancelled)
        case let .failed(error):
            hud.errorDetails = error.localizedDescription
            speaker?.stop()
            dispatch(.failed(friendlyMessage(for: error)))
        }
    }

    /// Whether the answer is spoken in the current mode.
    var shouldSpeak: Bool {
        switch currentMode {
        case .voice: settings.speakAnswers
        case .text: settings.speakTextAnswers
        }
    }

    /// In the voice mode the dangerous actions can be rejected without asking.
    private func handleApprovalRequest(_ request: ServerRequest) {
        guard currentMode == .voice, settings.approvalPolicy == .denyInVoice else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self else { return }
            await self.respond(to: request, with: .approval(choice: "deny"))
            self.speakNow("Действие отклонено")
        }
    }

    /// Which session the request goes to.
    ///
    /// With «продолжать последнюю сессию» a voice request continues the current chat,
    /// without it every voice request starts a new one. A text request always continues
    /// the current chat.
    func resolveSession(
        text: String,
        mode: PromptMode,
        manager: TransportManager,
        freshSession: Bool = false
    ) async throws -> SessionID? {
        if freshSession {
            return try? await manager.newSession(title: Self.sessionTitle(for: text))
        }
        let current = chats.currentSessionID
        let existing: SessionID? = switch mode {
        case .voice:
            settings.continueLastSession && !current.isEmpty ? current : nil
        case .text:
            current.isEmpty ? nil : current
        }
        if let existing {
            return existing
        }
        return try? await manager.newSession(title: Self.sessionTitle(for: text))
    }

    /// Title of a new session: the first words of the prompt.
    static func sessionTitle(for text: String) -> String {
        let words = text
            .split(separator: " ", omittingEmptySubsequences: true)
            .prefix(6)
            .joined(separator: " ")
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "gerania" }
        return trimmed.count > 60 ? String(trimmed.prefix(60)) : trimmed
    }

    /// Sessions of Hermes for the list of chats.
    func chatSessions() async -> [SessionSummary] {
        do {
            let manager = try await makeTransport()
            return try await manager.sessions(limit: 50)
        } catch {
            Log.hermes.info("cannot list sessions: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Push to talk: the same as the wake word.
    public func pushToTalk() {
        dispatch(.wake(at: Date().timeIntervalSince1970))
    }

    /// Plays a fixture with the speed of a real answer.
    func streamFixture(_ text: String, named name: String) async {
        var index = text.startIndex
        var slowest = 0.0
        while index < text.endIndex {
            if Task.isCancelled {
                return
            }
            let end = text.index(index, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[index ..< end])
            index = end
            hud.appendDelta(chunk)
            dispatch(.textDelta(chunk))
            slowest = max(slowest, HUDProfiler.lastDuration)
            try? await Task.sleep(for: .milliseconds(30))
        }
        hud.flushStream()
        Log.ui.info("fixture \(name, privacy: .public): slowest update \(slowest, privacy: .public) ms")
        dispatch(.completed(finalText: text))
    }
}
