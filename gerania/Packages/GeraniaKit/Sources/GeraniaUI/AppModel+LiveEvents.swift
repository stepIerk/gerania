import Foundation
import GeraniaCore
import RealtimeKit

/// Routing of Gemini Live events into the HUD and the dialog state machine.
extension AppModel {
    func handleLiveLevel(_ level: Double) {
        guard isLiveActive || liveStartTask != nil else {
            return
        }
        let normalized = min(1, max(0, level))
        levelSmoother.update(Float(normalized))
        hud.micLevel = normalized > 0.02 ? levelSmoother.level : 0
    }

    func handleLiveSpeaking(_ speaking: Bool) {
        liveSpeaking = speaking
        guard isLiveActive else {
            return
        }
        if speaking {
            if case .speaking = state {
                return
            }
            apply(state: .speaking)
        } else {
            if case .speaking = state {
                apply(state: .listening(deadline: Date().timeIntervalSince1970 + 3600))
                flushLiveNotes()
            }
            // The goodbye is fully played: the dialog can close now.
            maybeCommitLiveEnd()
        }
    }

    func handleLive(_ event: LiveEvent) {
        guard liveConversation != nil || liveStartTask != nil else {
            return
        }
        switch event {
        case let .inputTranscript(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            // A new phrase means the dialog continues: drop a pending goodbye.
            cancelLiveEnd()
            liveTurnFinished = false
            liveEndDetector.addUser(trimmed)
            let end = LiveEndMatcher.isEnd(trimmed)
            // «Пока» and «до свидания» are farewells, not an abrupt stop: let
            // Gera answer and close the dialog after the goodbye.
            let stop = !end && LiveStopMatcher.isStop(trimmed)
            Log.voice.debug("live: input \(trimmed, privacy: .public) stop=\(stop) end=\(end)")
            hud.heardText = trimmed
            if stop {
                Log.voice.notice("live: stop phrase detected")
                Task { await finishLive(reason: "Остановлено") }
            }
        case let .outputTranscript(text):
            hud.appendDelta(text)
            if case .listening = state {
                apply(state: .streaming)
            }
        case .interrupted:
            cancelLiveEnd()
            liveEndDetector.reset()
            liveTurnFinished = false
            hud.hint = "Перебито"
            if case .speaking = state {
                apply(state: .listening(deadline: Date().timeIntervalSince1970 + 3600))
            }
        case .turnComplete:
            liveTurnFinished = true
            if liveEndDetector.finishTurn() {
                requestLiveEnd(reason: "Диалог завершён")
            }
            if case .streaming = state {
                apply(state: .listening(deadline: Date().timeIntervalSince1970 + 3600))
            }
            if case .speaking = state {
                break
            }
            flushLiveNotes()
            maybeCommitLiveEnd()
        case let .toolCall(calls):
            handleLiveToolCalls(calls)
        case let .toolCallCancellation(ids):
            Log.voice.info("live: tool calls cancelled \(ids.count)")
        case let .goAway(seconds):
            hud.hint = seconds.map { "Сессия Gemini закончится через \(Int($0)) с" }
                ?? "Сессия Gemini скоро закончится"
        case .usage:
            break
        case let .error(error):
            Log.voice.error("live error: \(error.localizedDescription, privacy: .public)")
            hud.hint = error.localizedDescription
            if isLiveActive {
                Task { await finishLive(reason: error.localizedDescription) }
            }
        case let .closed(reason):
            guard isLiveActive else { return }
            Task { await finishLive(reason: reason ?? "Диалог завершён") }
        case .audio, .setupComplete, .resumptionUpdate:
            break
        }
    }
}
