import Foundation
import GeraniaCore
import RealtimeKit

/// Free Gemini keys limit every Live model per minute: when one model runs out,
/// Gera moves to the next one and, when all are paused, answers in the classic
/// Whisper + Hermes mode and says until when.
extension AppModel {
    /// The first Live model that is not paused for its limit.
    func availableLiveModel(now: Date = Date()) throws -> String {
        if NetworkStatus.shared.isOffline {
            throw LiveError.network("нет подключения к интернету")
        }
        guard let model = liveQuota.pick(preferred: settings.liveModel, now: now) else {
            throw LiveError.quotaExceeded
        }
        return model
    }

    /// Marks `model` as exhausted and starts the next one, when the microphone
    /// is still with the ears. Returns whether a retry took over.
    func retryLiveAfterQuota(_ error: Error, seed: String?, key: String, model: String) async -> Bool {
        guard (error as? LiveError) == .quotaExceeded else { return false }
        liveQuota.markExhausted(model)
        guard !voiceIsSuspended, let next = liveQuota.pick(preferred: settings.liveModel) else {
            return false
        }
        Log.voice.notice("live: quota on \(model, privacy: .public), trying \(next, privacy: .public)")
        hud.hint = "Лимит \(LiveModelCatalog.title(of: model)) — переключаюсь на \(LiveModelCatalog.title(of: next))"
        hud.modelLabel = next
        await runLiveStart(seed: seed, key: key, model: next)
        return true
    }

    /// A limit hit in the middle of a dialog pauses the model for the next wake.
    func noteLiveError(_ error: LiveError) {
        guard error == .quotaExceeded, let model = liveActiveModel else { return }
        liveQuota.markExhausted(model)
    }

    /// The HUD hint after a failed start.
    func liveFailureHint(_ error: Error) -> String {
        guard (error as? LiveError) == .quotaExceeded else {
            return "\(error.localizedDescription) — обычный режим"
        }
        return Self.quotaHint(until: liveQuota.nextAvailableDate(preferred: settings.liveModel))
    }

    static func quotaHint(until date: Date?) -> String {
        guard let date else {
            return "Лимит Gemini Live исчерпан — отвечаю в обычном режиме"
        }
        let time = date.formatted(date: .omitted, time: .shortened)
        return "Лимит Gemini Live исчерпан — до \(time) отвечаю в обычном режиме"
    }
}
