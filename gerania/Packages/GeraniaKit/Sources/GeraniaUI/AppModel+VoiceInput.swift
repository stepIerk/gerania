import Foundation
import GeraniaCore
import VoiceKit

/// Microphone input: hotkeys, listen modes, the owner voice and the live gate.
///
/// ⌃⌥G talks (tap — Gera listens to one phrase, hold — while held),
/// ⌃⌥⇧G stops the answer, ⌃⌥⌘G turns the microphone off and on.
public extension AppModel {
    // MARK: - Hotkeys

    func talkKeyDown() {
        voiceInput.talkPressedAt = Date()
        if isLiveActive {
            if voiceInput.settings.listenMode == .pushToTalk {
                voiceInput.liveTalkLatched.toggle()
            } else if liveSpeaking {
                // Talking over Gera: she stops at once, the microphone stays open.
                liveConversation?.interruptSpeech()
            }
            updateLiveInputGate()
            return
        }
        guard liveConversation == nil, liveStartTask == nil else { return }
        wakeByHotkey()
    }

    func talkKeyUp() {
        guard let pressed = voiceInput.talkPressedAt else { return }
        voiceInput.talkPressedAt = nil
        let held = Date().timeIntervalSince(pressed) >= VoiceInputController.holdThreshold
        if isLiveActive {
            if held, voiceInput.settings.listenMode == .pushToTalk {
                voiceInput.liveTalkLatched = false
            }
            updateLiveInputGate()
            return
        }
        if held {
            // Hold to talk: the release ends the phrase, no need to wait for a pause.
            Task { await voiceBridge?.send(.flush) }
        }
    }

    /// Stops the answer. In the live dialog the first press silences Gera and
    /// keeps the dialog; the second one, when she is quiet, ends it.
    func stopAnswer() {
        if isLiveActive {
            if liveSpeaking {
                liveConversation?.interruptSpeech()
                hud.hint = "Остановлено — говорите"
            } else {
                Task { await finishLive(reason: "Остановлено") }
            }
            return
        }
        if case .idle = state {
            speaker?.stop()
            return
        }
        speaker?.stop()
        stop()
    }

    func toggleMicrophone() {
        let enable = !settings.voiceEnabled
        Task {
            await setVoiceEnabled(enable)
            sounds?.play(enable ? .wake : .stop)
            Log.voice.notice("microphone toggled by hotkey: \(enable, privacy: .public)")
        }
    }

    /// The talk hotkey outside the live dialog: the same as «Гера» without the word.
    internal func wakeByHotkey() {
        guard settings.voiceEnabled, voiceBridge != nil, isVoiceRunning else {
            dispatch(.wake(at: Date().timeIntervalSince1970))
            hud.hint = "Микрофон выключен — включите его сочетанием ⌃⌥⌘G или в меню Геры"
            return
        }
        if state.isBusy || state == .speaking {
            interruptTurn()
            speaker?.stop()
        }
        dispatch(.wake(at: Date().timeIntervalSince1970))
        Task { await voiceBridge?.send(.arm) }
        if settings.liveVoiceEnabled {
            startLiveDialog(seed: nil)
        }
    }

    // MARK: - Ears

    /// The Picovoice key and files for the ears process.
    internal func earsEnvironment() -> [String: String] {
        WakeEngine.environment(
            sensitivity: voiceInput.settings.keywordSensitivity,
            ownerThreshold: voiceInput.settings.ownerThreshold
        )
    }

    /// Listen mode and owner gate take effect at once, without a restart.
    func sendVoiceInputSettings() async {
        await voiceBridge?.send(.listenMode(voiceInput.settings.listenMode.rawValue))
        await voiceBridge?.send(.ownerGate(enabled: voiceInput.settings.ownerGateEnabled))
        updateLiveInputGate()
    }

    /// A new key, file, sensitivity or threshold needs a fresh ears process.
    func restartEars() async {
        guard voiceBridge != nil else { return }
        await voiceBridge?.stop()
        voiceBridge = nil
        setVoiceRunning(false)
        await startVoice()
    }

    internal func handleVoiceInputEvent(_ event: VoiceEvent) {
        switch event {
        case let .engines(keyword, keywordDetail, owner, ownerDetail):
            voiceInput.noteEngines(
                keyword: keyword,
                keywordDetail: keywordDetail,
                owner: owner,
                ownerDetail: ownerDetail
            )
            Log.voice.notice(
                "ears: keyword \(keywordDetail, privacy: .public), owner \(ownerDetail, privacy: .public)"
            )
        case let .wakeRejected(score):
            Log.voice.info("wake word rejected: foreign voice \(score, privacy: .public)")
        case let .speakerRejected(score):
            Log.voice.info("phrase rejected: foreign voice \(score, privacy: .public)")
            if case .listening = state {
                hud.hint = "Не узнала голос — команда не принята"
            }
        case let .speaker(who):
            voiceInput.liveOtherSpeaking = who == .other
            updateLiveInputGate()
        default:
            break
        }
    }

    // MARK: - Live gate

    /// Opens or closes the microphone of the live dialog by the listen mode,
    /// the hotkey and who is talking.
    internal func updateLiveInputGate() {
        guard let conversation = liveConversation else {
            voiceInput.liveTalkLatched = false
            voiceInput.liveOtherSpeaking = false
            return
        }
        let open = LiveInputPolicy.isOpen(
            mode: voiceInput.settings.listenMode,
            modelSpeaking: liveSpeaking,
            talkHeld: voiceInput.talkPressedAt != nil,
            talkLatched: voiceInput.liveTalkLatched,
            otherSpeaking: voiceInput.ownerGateActive && voiceInput.liveOtherSpeaking
        )
        conversation.setInputGate(open: open)
        hud.isLiveMicClosed = !open
    }
}
