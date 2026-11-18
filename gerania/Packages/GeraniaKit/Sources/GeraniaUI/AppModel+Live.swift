import Foundation
import GeraniaCore
import RealtimeKit

/// The part of the orchestrator that runs the live Gemini dialog.
extension AppModel {
    /// Starts the live dialog after the wake word.
    ///
    /// With `waitForPhrase` the ears keep the microphone until the user finishes
    /// the first phrase: the connection is ready by then, so Gemini receives the
    /// complete command instead of the fragment recognized at the wake moment.
    func startLiveDialog(seed: String?, waitForPhrase: Bool = true) {
        guard !isLiveActive, liveConversation == nil, liveStartTask == nil else {
            return
        }
        let key: String
        do {
            key = try LiveCredentials.loadAPIKey()
        } catch {
            Log.voice.error("live: credentials unavailable: \(error.localizedDescription, privacy: .public)")
            hud.hint = "\(error.localizedDescription) — обычный режим"
            // The ears still own the microphone: the classic pipeline finishes the
            // phrase, so the seed must not be sent a second time.
            if !waitForPhrase || voiceBridge == nil || !isVoiceRunning {
                Task { await fallbackFromLive(seed: seed) }
            }
            return
        }
        hud.reset()
        hud.heardText = nil
        hud.isLive = true
        hud.showsModel = settings.showActiveModelInHUD
        hud.modelLabel = settings.liveModel
        hud.hint = "Подключаюсь к Gemini…"
        apply(state: .listening(deadline: Date().timeIntervalSince1970 + 3600))
        panels?.presentHUD(state: state)
        livePendingText = trimmed(seed)
        liveSentText = nil
        let earsRunning = voiceBridge != nil && isVoiceRunning
        liveStartup.begin(skipWait: !waitForPhrase || !earsRunning)
        Log.voice.notice("live: start requested")
        liveStartTask = Task { [weak self] in
            await self?.runLiveStart(seed: seed, key: key)
        }
    }

    /// The HUD was closed by the user: the live dialog must not keep the microphone.
    func hudDidHide() {
        guard isLiveActive || liveConversation != nil || liveStartTask != nil else {
            return
        }
        Task { await finishLive(reason: nil) }
    }

    /// Ends the live dialog, returns the microphone to Python and hides the HUD.
    func finishLive(reason: String?) async {
        Log.voice.notice("live: finish requested: \(reason ?? "closed", privacy: .public)")
        let conversation = liveConversation
        liveConversation = nil
        liveStartTask?.cancel()
        liveStartTask = nil
        isLiveActive = false
        hud.isLive = false
        finishSuspendWait()
        liveNoteQueue.removeAll()
        livePendingText = nil
        liveSentText = nil
        liveStartup.finish()
        liveEndPending = nil
        liveEndWatchdog?.cancel()
        liveEndWatchdog = nil
        liveEndCommit?.cancel()
        liveEndCommit = nil
        liveTurnFinished = false
        liveSpeaking = false
        liveEndDetector.reset()
        if let conversation {
            await conversation.close(reason: reason)
        }
        await voiceBridge?.send(.resume)
        voiceIsSuspended = false
        if let reason, !reason.isEmpty {
            hud.hint = reason
        }
        if state != .idle {
            apply(state: .idle)
            panels?.dismissHUD(after: 0)
        }
        Log.voice.notice("live: dialog finished")
    }

    private func runLiveStart(seed: String?, key: String) async {
        defer { liveStartTask = nil }
        let session = LiveSessionConfiguration(
            apiKey: key,
            model: settings.liveModel,
            voiceName: settings.liveVoiceName,
            tools: LiveTools.all
        )
        let conversation = LiveConversation(
            configuration: LiveConversationConfiguration(
                session: session,
                echoMode: .automatic,
                idleTimeout: max(15, settings.liveIdleSeconds),
                maxDuration: 1800
            )
        )
        conversation.onEvent = { [weak self] event in
            self?.handleLive(event)
        }
        conversation.onLevel = { [weak self] level in
            self?.handleLiveLevel(level)
        }
        conversation.onSpeakingChanged = { [weak self] speaking in
            self?.handleLiveSpeaking(speaking)
        }
        liveConversation = conversation
        do {
            // Connect while the ears are still transcribing the first phrase.
            try await conversation.prepare()
            guard !Task.isCancelled, liveConversation === conversation else {
                await conversation.close(reason: "отменено")
                return
            }
            hud.hint = "Слушаю…"
            await waitForLiveHandoff()
            guard !Task.isCancelled, liveConversation === conversation else {
                await conversation.close(reason: "отменено")
                return
            }
            if !liveStartup.canHandOff {
                Log.voice.notice("live: handoff timeout, switching mid-phrase")
            }
            // The phrase is complete: only now does Gemini get the microphone.
            await suspendEarsForLive()
            guard !Task.isCancelled, liveConversation === conversation else {
                await conversation.close(reason: "отменено")
                return
            }
            Log.voice.notice("live: ears suspended, starting audio")
            try await conversation.startListening()
            guard conversation.isPrepared else {
                throw LiveError.sessionClosed("сессия закрылась при запуске")
            }
            guard !Task.isCancelled, liveConversation === conversation else {
                await conversation.close(reason: "отменено")
                return
            }
            isLiveActive = true
            try await flushLiveText(seed: seed, into: conversation)
            hud.hint = nil
            Log.voice.notice("live: ready")
        } catch {
            Log.voice.error("live: start failed: \(error.localizedDescription, privacy: .public)")
            await conversation.close(reason: error.localizedDescription)
            let cancelled = Task.isCancelled || liveConversation !== conversation
            if liveConversation === conversation {
                liveConversation = nil
            }
            guard !cancelled else {
                return
            }
            isLiveActive = false
            hud.isLive = false
            hud.hint = "\(error.localizedDescription) — обычный режим"
            await fallbackFromLive(seed: seed)
        }
    }

    /// Waits for the first phrase to be fully recognized.
    private func waitForLiveHandoff(timeout: TimeInterval = 20) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !liveStartup.canHandOff, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// The failed live start returns the phrase to the classic pipeline.
    private func fallbackFromLive(seed: String?) async {
        if liveStartup.isTracking, !liveStartup.canHandOff,
           voiceBridge != nil, isVoiceRunning
        {
            await waitForLiveHandoff()
        }
        let text = preferredLiveText(seed: seed)
        // Clear the live state before `handleCommand`: it must take the classic path.
        liveStartTask = nil
        liveStartup.finish()
        livePendingText = nil
        await voiceBridge?.send(.resume)
        voiceIsSuspended = false
        if let text, !text.isEmpty {
            handleCommand(text)
        } else {
            Task { await voiceBridge?.send(.arm) }
            dispatch(.wake(at: Date().timeIntervalSince1970))
        }
    }

    /// Remembers text that belongs to the wake phrase while live is still starting.
    func acceptLiveText(_ text: String) {
        guard let text = trimmed(text), !text.isEmpty else {
            return
        }
        if let conversation = liveConversation, isLiveActive {
            let new = liveTextKey(text)
            let sent = liveTextKey(liveSentText ?? "")
            guard new != sent, !sent.hasPrefix(new) else {
                return
            }
            liveSentText = text
            Task { [weak self] in
                do {
                    try await conversation.sendText(text)
                } catch {
                    self?.handleLive(.error(.network(error.localizedDescription)))
                }
            }
            return
        }
        guard liveConversation != nil || liveStartTask != nil else {
            return
        }
        liveStartup.note(text)
    }

    private func flushLiveText(seed: String?, into conversation: LiveConversation) async throws {
        let text = preferredLiveText(seed: seed)
        guard let text, !text.isEmpty else {
            livePendingText = nil
            liveStartup.finish()
            return
        }
        let key = liveTextKey(text)
        guard key != liveTextKey(liveSentText ?? "") else {
            livePendingText = nil
            liveStartup.finish()
            return
        }
        liveSentText = text
        try await conversation.sendText(text)
        livePendingText = nil
        liveStartup.finish()
        Log.voice.notice("live: first phrase sent")
    }

    private func preferredLiveText(seed: String?) -> String? {
        if let transcript = trimmed(liveStartup.transcript) {
            return transcript
        }
        if let pending = trimmed(livePendingText) {
            return pending
        }
        return trimmed(seed)
    }

    private func trimmed(_ text: String?) -> String? {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func liveTextKey(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func suspendEarsForLive() async {
        guard let bridge = voiceBridge, !voiceIsSuspended else {
            return
        }
        await bridge.send(.suspend)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if voiceIsSuspended {
                continuation.resume()
                return
            }
            voiceSuspendContinuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.finishSuspendWait()
            }
        }
    }

    /// Called when Python confirms `suspend` or the wait times out.
    func finishSuspendWait() {
        voiceSuspendContinuation?.resume()
        voiceSuspendContinuation = nil
    }
}
