import Foundation
import GeraniaCore
import HermesKit
import RealtimeKit
import VoiceKit

/// The part of the orchestrator that listens to the voice front-end.
///
/// The decisions (wake, stop, command) are made in Python; the application only reacts.
public extension AppModel {
    /// Starts the voice front-end.
    func startVoice() async {
        guard settings.voiceEnabled else { return }
        if !MicrophoneAccess.isAuthorized {
            Log.voice.info("microphone status: \(MicrophoneAccess.statusName, privacy: .public)")
        }
        guard await microphoneRequest() else {
            Log.voice.error("microphone access denied")
            hud.hint = "Нет доступа к микрофону — разрешите его в Системных настройках"
            return
        }
        if voiceBridge == nil {
            let bridge = VoiceBridge(
                configuration: VoiceBridge.Configuration(
                    pythonPath: settings.pythonPath,
                    scriptOverridePath: settings.earsScriptOverridePath
                )
            )
            voiceBridge = bridge
            let stream = await bridge.events()
            Task { @MainActor [weak self] in
                for await event in stream {
                    self?.handleVoice(event)
                }
            }
        }
        await voiceBridge?.start()
        await voiceBridge?.send(.config(values: settings.microphoneThresholds))
        await voiceBridge?.send(.state(busy: false, speaking: false))
        lastVoiceBusy = false
        lastVoiceSpeaking = false
        voiceIsSuspended = false
        setVoiceRunning(true)
    }

    /// Stops the voice front-end (the menu bar mute).
    func stopVoice() async {
        if isLiveActive || liveConversation != nil || liveStartTask != nil {
            await finishLive(reason: nil)
        }
        await voiceBridge?.stop()
        setVoiceRunning(false)
    }

    /// Starts Gera: the ears listen, the panels answer.
    ///
    /// The button in the app window calls it, so the microphone is asked only when
    /// the user asks for it.
    func startGera() async {
        settings.voiceEnabled = true
        await startVoice()
        // Onboarding step: reminders need banners. A refusal only changes the
        // status line in «Планы»; the HUD card still shows the result.
        await notificationRequest?()
        if isVoiceRunning {
            setLaunchError(nil)
            return
        }
        setLaunchError(
            MicrophoneAccess.isDenied
                ? "Нет доступа к микрофону — разрешите его в Системных настройках"
                : "Не удалось запустить голос: проверьте микрофон и окружение голоса"
        )
    }

    /// Stops Gera: the ears go silent, the app stays in the menu bar.
    func stopGera() async {
        settings.voiceEnabled = false
        setLaunchError(nil)
        await stopVoice()
    }

    /// Turns the microphone on or off.
    func setVoiceEnabled(_ enabled: Bool) async {
        if enabled {
            await startVoice()
        } else {
            await stopVoice()
        }
    }

    /// Handles one event of the voice front-end.
    internal func handleVoice(_ event: VoiceEvent) {
        switch event {
        case let .ready(model):
            Log.voice.info("voice ready: \(model, privacy: .public)")
            if isLiveActive || liveStartTask != nil || liveConversation != nil {
                Task { await voiceBridge?.send(.suspend) }
                // The restarted ears will not send `utterance_end` for the phrase
                // collected before the restart: do not wait for it.
                if liveStartup.isTracking, !isLiveActive {
                    liveStartup.forceHandoff()
                }
            }
        case let .level(rms, threshold, active):
            handleLevel(rms: rms, threshold: threshold, active: active)
        case .utteranceStart:
            liveStartup.utteranceStarted()
        case let .utteranceEnd(duration):
            Log.voice.debug("voice utterance \(duration, privacy: .public) s")
            if liveStartup.isTracking {
                liveStartup.utteranceEnded()
                // The connection may be slower than the phrase: keep the ears
                // awaiting so a continuation is recognized too, until the
                // microphone is handed over to Gemini.
                if !isLiveActive {
                    Task { await voiceBridge?.send(.arm) }
                }
            }
        case let .filtered(reason):
            hud.hint = reason
        case let .transcript(text, _, _):
            Log.voice.debug("voice heard: \(text, privacy: .public)")
        case let .wake(inlineCommand):
            handleWake(inlineCommand: inlineCommand)
        case let .partial(text):
            handlePartial(text)
        case let .command(text, _):
            handleCommand(text)
        case let .stop(scope):
            handleStop(scope: scope)
        case .awaitTimeout:
            guard !isLiveActive, liveStartTask == nil else { return }
            hud.hint = "Команда не прозвучала"
            sounds?.play(.stop)
            dispatch(.dismissed)
        case .suspended:
            Log.voice.info("voice suspended for live session")
            voiceIsSuspended = true
            finishSuspendWait()
        case .resumed:
            Log.voice.info("voice resumed after live session")
            voiceIsSuspended = false
        case let .error(message):
            hud.hint = message
        case .bye:
            Log.voice.info("voice script finished")
        }
    }

    private func handleLevel(rms: Double, threshold: Double, active: Bool) {
        guard threshold > 0 else { return }
        let now = Date()
        if now.timeIntervalSince(lastLevelLog) > 1 {
            lastLevelLog = now
            Log.voice.info("level \(rms, privacy: .public) thr \(threshold, privacy: .public)")
        }
        let normalized = min(1, max(0, rms / threshold))
        // Сглаживание живёт в модели: вью получает уже ровный уровень.
        levelSmoother.update(Float(normalized))
        hud.micLevel = active ? levelSmoother.level : 0
    }

    private func handleWake(inlineCommand: String?) {
        guard liveConversation == nil, liveStartTask == nil, !isLiveActive else {
            return
        }
        if state.isBusy || state == .speaking {
            interruptTurn()
            speaker?.stop()
            hud.hint = "Прервано новым запросом"
        }
        let inline = inlineCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Пока человек ещё говорит, звук не играем: он попадёт в микрофон и
        // оборвёт команду. Подтверждение придёт куском «sent», когда команда
        // уйдёт агенту.
        if inline.isEmpty {
            sounds?.play(.wake)
        }
        // Панель показываем сразу: команда может прийти отдельным событием.
        dispatch(.wake(at: Date().timeIntervalSince1970))
        if settings.liveVoiceEnabled {
            startLiveDialog(seed: inlineCommand)
        }
    }

    /// The text recognized while the user is still speaking: show it right away.
    private func handlePartial(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hud.heardText = trimmed
        if liveConversation != nil || liveStartTask != nil || isLiveActive {
            acceptLiveText(trimmed)
        }
    }

    internal func handleCommand(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if liveConversation != nil || liveStartTask != nil || isLiveActive {
            if LiveStopMatcher.isStop(trimmed), !LiveEndMatcher.isEnd(trimmed) {
                Task { await finishLive(reason: "Остановлено") }
            } else {
                acceptLiveText(trimmed)
            }
            return
        }
        hud.heardText = trimmed
        sounds?.play(.sent)
        ask(trimmed, mode: .voice)
    }

    private func handleStop(scope: VoiceEvent.StopScope) {
        if isLiveActive || liveConversation != nil || liveStartTask != nil {
            Task { await finishLive(reason: "Остановлено") }
            return
        }
        switch scope {
        case .input:
            hud.hint = "Ввод отменён"
            sounds?.play(.stop)
            dispatch(.dismissed)
        case .busy, .explicit:
            interruptTurn()
            speaker?.stop()
            sounds?.play(.stop)
            hud.hint = "Остановлено"
            dispatch(.stop)
        }
    }

    /// Interrupts the running request without changing the state of the answer.
    internal func interruptTurn() {
        cancelTurn()
    }

    /// Speaks a short phrase right away.
    internal func speakNow(_ text: String) {
        speaker?.speakNow(text)
    }
}
