import Foundation
import GeraniaCore
import HermesKit
import Observation
import RealtimeKit
import VoiceKit

/// Orchestrator shared by the menu bar, settings, the HUD panel and the mini window.
@MainActor
@Observable
public final class AppModel {
    public let settings: GeraSettings
    /// Content of the HUD panel.
    public let hud: HUDViewModel
    /// List of the chats.
    public let chats: ChatsModel
    public private(set) var state: GeraState = .idle
    public private(set) var lastServerRequest: ServerRequest?
    /// Whether the voice front-end is running right now: the ears listen for the wake word.
    public private(set) var isVoiceRunning = false
    /// Whether the microphone belongs to the live Gemini dialog right now.
    public var isLiveActive = false
    /// Why the last launch attempt failed, for the window of the application.
    public private(set) var launchError: String?
    /// Remembers the state of the voice front-end.
    func setVoiceRunning(_ running: Bool) {
        isVoiceRunning = running
    }

    /// Remembers why the launch failed.
    func setLaunchError(_ message: String?) {
        launchError = message
    }

    /// Window layer. Weak: the owner (app root) keeps it alive.
    @ObservationIgnored public weak var panels: PanelPresenting?

    @ObservationIgnored var transport: TransportManager?
    @ObservationIgnored public var voiceBridge: VoiceBridge?
    @ObservationIgnored public var speaker: Speaker?
    @ObservationIgnored public var sounds: SoundPlayer?
    /// Asks the system for the microphone. A seam for the tests: they must not
    /// show a permission dialog.
    @ObservationIgnored var microphoneRequest: () async -> Bool = {
        if MicrophoneAccess.isAuthorized {
            return true
        }
        return await MicrophoneAccess.request()
    }

    /// Asks for notifications when the person starts Gera. Set by the app
    /// root; `nil` in the tests, which must not touch the notification center.
    @ObservationIgnored var notificationRequest: (() async -> Void)?

    @ObservationIgnored public var currentMode: PromptMode = .text
    @ObservationIgnored var lastLevelLog = Date.distantPast
    @ObservationIgnored var levelSmoother = LevelSmoother()
    @ObservationIgnored var listenTimeoutTask: Task<Void, Never>?
    @ObservationIgnored var transportKind: TransportKind?
    @ObservationIgnored var activeCandidate: ModelCandidate?
    /// Provider of the model that is answering right now, if a turn is running.
    public var activeProvider: String? {
        activeCandidate?.provider
    }

    /// Health of the fallback list: which models are cooling down and why.
    @ObservationIgnored let modelHealth = ModelHealthStore()
    /// Journal of the tools that ran on this Mac.
    @ObservationIgnored public let auditLog: AuditLog
    /// Curated memory: the profile of the person and the notes of the agent.
    public let memory: MemoryModel
    @ObservationIgnored var turnTask: Task<Void, Never>?
    /// Ten-minute reminder for `computer_use`.
    @ObservationIgnored var computerUseTask: Task<Void, Never>?
    @ObservationIgnored var activeSessionID: SessionID?
    @ObservationIgnored var lastPrompt: String?
    @ObservationIgnored public var liveConversation: LiveConversation?
    @ObservationIgnored var liveTaskManager: LiveTaskManager?
    @ObservationIgnored var liveStartTask: Task<Void, Never>?
    @ObservationIgnored var livePendingText: String?
    @ObservationIgnored var liveSentText: String?
    @ObservationIgnored var liveStartup = LiveStartup()
    @ObservationIgnored var liveQuota = LiveQuotaGuard()
    @ObservationIgnored public let voiceInput = VoiceInputController()
    @ObservationIgnored var liveActiveModel: String?
    @ObservationIgnored var voiceIsSuspended = false
    @ObservationIgnored var voiceSuspendContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored var liveNoteQueue: [String] = []
    @ObservationIgnored var thinkingCueTask: Task<Void, Never>?
    @ObservationIgnored var lastVoiceBusy = false
    @ObservationIgnored var lastVoiceSpeaking = false
    @ObservationIgnored var liveEndDetector = LiveEndDetector()
    @ObservationIgnored var liveEndPending: String?
    @ObservationIgnored var liveEndWatchdog: Task<Void, Never>?
    @ObservationIgnored var liveEndCommit: Task<Void, Never>?
    @ObservationIgnored var liveTurnFinished = false
    @ObservationIgnored var liveSpeaking = false

    public init(
        settings: GeraSettings = GeraSettings(),
        hud: HUDViewModel = HUDViewModel(),
        chats: ChatsModel? = nil,
        auditLog: AuditLog? = nil,
        memoryStore: MemoryFileStore? = nil
    ) {
        self.settings = settings
        self.hud = hud
        self.chats = chats ?? ChatsModel(settings: settings)
        self.auditLog = auditLog ?? AuditLog()
        memory = MemoryModel(store: memoryStore ?? MemoryFileStore(limits: MemoryLimits.load()))
        speaker = Speaker()
        sounds = SoundPlayer()
        speaker?.onSpeakingChanged = { [weak self] speaking in
            self?.handleSpeakingChanged(speaking)
        }
        sounds?.onMute = { [weak self] seconds in
            guard let self else { return }
            Task { await self.voiceBridge?.send(.mute(seconds: seconds, keepPhrase: true)) }
        }
        applyVoiceSettings()
        hud.onAction = { [weak self] action in
            self?.perform(action)
        }
    }

    public func dispatch(_ action: GeraAction) {
        switch action {
        case .turnStarted, .completed, .cancelled, .stop, .failed, .dismissed:
            stopComputerUseWatch()
        default:
            break
        }
        if isLiveActive || liveStartTask != nil {
            switch action {
            case .dismissed, .stop:
                Task { [weak self] in
                    await self?.finishLive(reason: nil)
                }
            case .wake:
                return
            default:
                break
            }
        }
        let (next, effects) = reduce(state: state, action: action)
        apply(state: next)
        if case let .serverRequest(request) = action {
            lastServerRequest = request
        }
        if case .serverRequestAnswered = action {
            lastServerRequest = nil
        }
        apply(effects)
    }

    public func openInput(prefill: String = "", showChats: Bool = false) {
        Log.ui.info("openInput requested")
        panels?.presentInput(prefill: prefill, showChats: showChats)
    }

    public func newChat() {
        settings.lastSessionID = ""
        panels?.dismissDetail()
        dispatch(.dismissed)
        Log.ui.info("newChat requested")
    }

    func apply(state next: GeraState) {
        let previous = state
        state = next
        panels?.updateHUD(state: next)
        updateVoiceLevels()
        scheduleListenTimeout(for: next)
        syncVoiceState(for: next)
        scheduleThinkingCue(for: next)
        playTransitionCue(from: previous, to: next)
    }

    /// Tells the ears whether the agent works and whether Gera speaks.
    ///
    /// The state used to be sent only when the speech started or stopped, so in
    /// the text mode `busy` stayed false forever and a bare «стоп» was ignored.
    func syncVoiceState(for next: GeraState) {
        let speaking = next == .speaking || speaker?.isSpeaking == true
        let busy = next.isBusy || speaking
        guard busy != lastVoiceBusy || speaking != lastVoiceSpeaking else { return }
        lastVoiceBusy = busy
        lastVoiceSpeaking = speaking
        guard let voiceBridge else { return }
        Task { await voiceBridge.send(.state(busy: busy, speaking: speaking)) }
    }

    /// A quiet «still working» cue after a second of thinking.
    ///
    /// Alexa does the same: the earcon appears only when the answer does not
    /// start immediately, so a fast reply is not covered by sounds.
    func scheduleThinkingCue(for next: GeraState) {
        thinkingCueTask?.cancel()
        thinkingCueTask = nil
        guard case .thinking = next, currentMode == .voice || isLiveActive else { return }
        thinkingCueTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self, case .thinking = self.state else { return }
            self.sounds?.play(.thinking)
        }
    }

    /// The cue of a state change: the answer is ready or something failed.
    func playTransitionCue(from previous: GeraState, to next: GeraState) {
        switch next {
        case .error:
            if case .error = previous {
                return
            }
            sounds?.play(.error)
        case .done:
            // After the speech the answer is already heard: no extra cue.
            if case .speaking = previous {
                return
            }
            if case .done = previous {
                return
            }
            sounds?.play(.done)
        default:
            break
        }
    }

    /// Слушаем ровно столько, сколько разрешили: дальше состояние само уходит в idle.
    func scheduleListenTimeout(for next: GeraState) {
        listenTimeoutTask?.cancel()
        listenTimeoutTask = nil
        guard case let .listening(deadline) = next else { return }
        let delay = max(0, deadline - Date().timeIntervalSince1970)
        listenTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.dispatch(.listenTimedOut)
        }
    }

    /// The microphone level is needed only while the HUD listens.
    func updateVoiceLevels() {
        guard let voiceBridge else { return }
        let isListening = if case .listening = state {
            true
        } else {
            false
        }
        Task { await voiceBridge.send(isListening ? .levelsOn : .levelsOff) }
    }

    func apply(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .startListening:
                Log.voice.debug("effect: startListening")
            case .stopListening:
                Log.voice.debug("effect: stopListening")
            case .cancelTranscription:
                Log.voice.debug("effect: cancelTranscription")
            case .interrupt:
                Log.hermes.debug("effect: interrupt")
            case .stopSpeaking:
                Log.speech.debug("effect: stopSpeaking")
            case let .playSound(cue):
                Log.ui.debug("effect: playSound \(cue.rawValue, privacy: .public)")
            case .showPanel:
                panels?.presentHUD(state: state)
            case let .hidePanel(delay):
                panels?.dismissHUD(after: adjustedHideDelay(delay))
            }
        }
    }

    /// The synthesizer started or stopped talking.
    func handleSpeakingChanged(_ speaking: Bool) {
        dispatch(speaking ? .speechStarted : .speechFinished)
    }

    /// Applies the settings of the speech to the speaker.
    func applyVoiceSettings() {
        speaker?.apply(
            Speaker.Settings(
                voiceName: settings.voiceName,
                rate: settings.speechRate,
                maxCharacters: settings.maxSpokenChars,
                isEnabled: settings.speakAnswers
            )
        )
    }

    /// Long answers need more time on screen: one extra second per 200 characters.
    func adjustedHideDelay(_ base: TimeInterval) -> TimeInterval {
        guard base > 0 else { return base }
        let extra = min(24, Double(hud.streamedText.count) / 200)
        return min(30, base + extra)
    }
}
