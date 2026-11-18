import Foundation
import Observation

/// User-facing settings persisted in `UserDefaults`.
///
/// `launchAtLogin` is a mirror only: the source of truth is `SMAppService.mainApp.status`.
@MainActor
@Observable
public final class GeraSettings {
    private enum Key {
        static let hermesPath = "hermesPath"
        static let transport = "transport"
        static let provider = "provider"
        static let model = "model"
        static let workdir = "workdir"
        static let voicePromptPrefix = "voicePromptPrefix"
        static let textPromptPrefix = "textPromptPrefix"
        static let continueLastSession = "continueLastSession"
        static let panelPosition = "panelPosition"
        static let panelDesignVersion = "panelDesignVersion"
        static let detailPanelWidth = "detailPanelWidth"
        static let detailPanelMargin = "detailPanelMargin"
        static let autoHideSeconds = "autoHideSeconds"
        static let maxPanelHeightFraction = "maxPanelHeightFraction"
        static let speakAnswers = "speakAnswers"
        static let voiceName = "voiceName"
        static let speechRate = "speechRate"
        static let maxSpokenChars = "maxSpokenChars"
        static let voiceEnabled = "voiceEnabled"
        static let liveVoiceEnabled = "liveVoiceEnabled"
        static let liveModel = "liveModel"
        static let liveVoiceName = "liveVoiceName"
        static let liveIdleSeconds = "liveIdleSeconds"
        static let pythonPath = "pythonPath"
        static let earsScriptOverridePath = "earsScriptOverridePath"
        static let launchAtLogin = "launchAtLogin"
        static let notifications = "notifications"
        static let approvalPolicy = "approvalPolicy"
        static let lastSessionID = "lastSessionID"
        static let promptHistory = "promptHistory"
        static let terminalApp = "terminalApp"
        static let experimentalDesktopKeys = "experimentalDesktopKeys"
        static let speakTextAnswers = "speakTextAnswers"
        static let micMinRMS = "micMinRMS"
        static let micNoiseMultiplier = "micNoiseMultiplier"
        static let micBandRatioMin = "micBandRatioMin"
        static let micFlatnessMax = "micFlatnessMax"
        static let micMinTonalFrames = "micMinTonalFrames"
        static let micMinTonalFraction = "micMinTonalFraction"
        static let micNoSpeechMax = "micNoSpeechMax"
        static let micLogprobMin = "micLogprobMin"
        static let modelCandidates = "modelCandidates"
        static let showActiveModelInHUD = "showActiveModelInHUD"
    }

    @ObservationIgnored private let store: DefaultsStore

    public var hermesPath: String {
        didSet { store.set(hermesPath, for: Key.hermesPath) }
    }

    public var transport: TransportKind {
        didSet { store.set(transport.rawValue, for: Key.transport) }
    }

    public var provider: String {
        didSet { store.set(provider, for: Key.provider) }
    }

    public var model: String {
        didSet { store.set(model, for: Key.model) }
    }

    public var workdir: String {
        didSet { store.set(workdir, for: Key.workdir) }
    }

    public var voicePromptPrefix: String {
        didSet { store.set(voicePromptPrefix, for: Key.voicePromptPrefix) }
    }

    public var textPromptPrefix: String {
        didSet { store.set(textPromptPrefix, for: Key.textPromptPrefix) }
    }

    public var continueLastSession: Bool {
        didSet { store.set(continueLastSession, for: Key.continueLastSession) }
    }

    public var panelPosition: PanelPosition {
        didSet { store.set(panelPosition.rawValue, for: Key.panelPosition) }
    }

    /// Width of the large answer window.
    public var detailPanelWidth: Double {
        didSet { store.set(detailPanelWidth, for: Key.detailPanelWidth) }
    }

    /// Gap between the large answer window and the right edge of the screen.
    public var detailPanelMargin: Double {
        didSet { store.set(detailPanelMargin, for: Key.detailPanelMargin) }
    }

    public var autoHideSeconds: Double {
        didSet { store.set(autoHideSeconds, for: Key.autoHideSeconds) }
    }

    public var maxPanelHeightFraction: Double {
        didSet { store.set(maxPanelHeightFraction, for: Key.maxPanelHeightFraction) }
    }

    public var speakAnswers: Bool {
        didSet { store.set(speakAnswers, for: Key.speakAnswers) }
    }

    public var voiceName: String {
        didSet { store.set(voiceName, for: Key.voiceName) }
    }

    public var speechRate: Double {
        didSet { store.set(speechRate, for: Key.speechRate) }
    }

    public var maxSpokenChars: Int {
        didSet { store.set(maxSpokenChars, for: Key.maxSpokenChars) }
    }

    public var voiceEnabled: Bool {
        didSet { store.set(voiceEnabled, for: Key.voiceEnabled) }
    }

    /// Whether the wake word opens a live Gemini dialog instead of the classic pipeline.
    public var liveVoiceEnabled: Bool {
        didSet { store.set(liveVoiceEnabled, for: Key.liveVoiceEnabled) }
    }

    public var liveModel: String {
        didSet { store.set(liveModel, for: Key.liveModel) }
    }

    public var liveVoiceName: String {
        didSet { store.set(liveVoiceName, for: Key.liveVoiceName) }
    }

    /// Seconds of silence before the live dialog closes.
    public var liveIdleSeconds: Double {
        didSet { store.set(liveIdleSeconds, for: Key.liveIdleSeconds) }
    }

    public var pythonPath: String {
        didSet { store.set(pythonPath, for: Key.pythonPath) }
    }

    public var earsScriptOverridePath: String {
        didSet { store.set(earsScriptOverridePath, for: Key.earsScriptOverridePath) }
    }

    public var launchAtLogin: Bool {
        didSet { store.set(launchAtLogin, for: Key.launchAtLogin) }
    }

    public var notifications: Bool {
        didSet { store.set(notifications, for: Key.notifications) }
    }

    public var approvalPolicy: ApprovalPolicy {
        didSet { store.set(approvalPolicy.rawValue, for: Key.approvalPolicy) }
    }

    public var lastSessionID: String {
        didSet { store.set(lastSessionID, for: Key.lastSessionID) }
    }

    /// Terminal application for «Открыть в Терминале».
    public var terminalApp: TerminalPreference {
        didSet { store.set(terminalApp.rawValue, for: Key.terminalApp) }
    }

    /// Experimental way of opening a session in the Desktop: type the id by hand.
    public var experimentalDesktopKeys: Bool {
        didSet { store.set(experimentalDesktopKeys, for: Key.experimentalDesktopKeys) }
    }

    /// Whether the text answers are spoken as well.
    public var speakTextAnswers: Bool {
        didSet { store.set(speakTextAnswers, for: Key.speakTextAnswers) }
    }

    /// History of the sent prompts, newest first.
    public private(set) var promptHistory: PromptHistory

    /// Adds a prompt to the history and saves it.
    /// Порог тишины микрофона: чем ниже, тем чувствительнее.
    public var micMinRMS: Double {
        didSet { store.set(micMinRMS, for: Key.micMinRMS) }
    }

    /// Во сколько раз порог выше фонового шума.
    public var micNoiseMultiplier: Double {
        didSet { store.set(micNoiseMultiplier, for: Key.micNoiseMultiplier) }
    }

    /// Доля энергии речи в полосе 300–3400 Гц: чем ниже, тем охотнее фильтр.
    public var micBandRatioMin: Double {
        didSet { store.set(micBandRatioMin, for: Key.micBandRatioMin) }
    }

    /// «Плоскость» спектра: чем выше, тем больше терпимости к шуму.
    public var micFlatnessMax: Double {
        didSet { store.set(micFlatnessMax, for: Key.micFlatnessMax) }
    }

    /// Минимум «голосовых» кадров в фразе.
    public var micMinTonalFrames: Int {
        didSet { store.set(micMinTonalFrames, for: Key.micMinTonalFrames) }
    }

    /// Доля «голосовых» кадров среди громких.
    public var micMinTonalFraction: Double {
        didSet { store.set(micMinTonalFraction, for: Key.micMinTonalFraction) }
    }

    /// Порог уверенности Whisper в наличии речи.
    public var micNoSpeechMax: Double {
        didSet { store.set(micNoSpeechMax, for: Key.micNoSpeechMax) }
    }

    /// Порог уверенности Whisper в тексте.
    public var micLogprobMin: Double {
        didSet { store.set(micLogprobMin, for: Key.micLogprobMin) }
    }

    /// Модели, которые перебираются по очереди: первая — основная.
    ///
    /// Если у модели закончился лимит, Геря пробует следующую.
    public var modelCandidates: [String] {
        didSet { store.set(modelCandidates, for: Key.modelCandidates) }
    }

    /// Whether the HUD header shows the model that answers right now.
    public var showActiveModelInHUD: Bool {
        didSet { store.set(showActiveModelInHUD, for: Key.showActiveModelInHUD) }
    }

    /// Пороги микрофона одной пачкой — их получает скрипт командой `config`.
    public var microphoneThresholds: [String: Double] {
        [
            "min_rms": micMinRMS,
            "noise_mult": micNoiseMultiplier,
            "band_ratio_min": micBandRatioMin,
            "flatness_max": micFlatnessMax,
            "min_tonal_frames": Double(micMinTonalFrames),
            "min_tonal_frac": micMinTonalFraction,
            "no_speech_max": micNoSpeechMax,
            "logprob_min": micLogprobMin,
        ]
    }

    public func rememberPrompt(_ prompt: String) {
        var history = promptHistory
        history.add(prompt)
        promptHistory = history
        store.set(history.prompts, for: Key.promptHistory)
    }

    public init(defaults: UserDefaults = .standard) {
        store = DefaultsStore(defaults: defaults)
        hermesPath = store.string(Key.hermesPath) ?? ""
        transport = store.string(Key.transport).flatMap(TransportKind.init(rawValue:)) ?? .auto
        provider = store.string(Key.provider) ?? "gemini"
        model = store.string(Key.model) ?? "gemini-2.5-flash-lite"
        let storedWorkdir = store.string(Key.workdir) ?? "~/AgentWork"
        workdir = storedWorkdir
        voicePromptPrefix = store.string(Key.voicePromptPrefix)
            ?? Self.defaultVoicePromptPrefix(workdir: Self.expandedPath(storedWorkdir))
        textPromptPrefix = store.string(Key.textPromptPrefix) ?? ""
        continueLastSession = store.bool(Key.continueLastSession) ?? true
        panelPosition = store.string(Key.panelPosition).flatMap(PanelPosition.init(rawValue:)) ?? .notch
        detailPanelWidth = store.double(Key.detailPanelWidth) ?? 480
        detailPanelMargin = store.double(Key.detailPanelMargin) ?? 0
        autoHideSeconds = store.double(Key.autoHideSeconds) ?? 6
        maxPanelHeightFraction = store.double(Key.maxPanelHeightFraction) ?? 0.6
        speakAnswers = store.bool(Key.speakAnswers) ?? true
        voiceName = store.string(Key.voiceName) ?? "Milena"
        speechRate = store.double(Key.speechRate) ?? 0.5
        maxSpokenChars = store.int(Key.maxSpokenChars) ?? 500
        voiceEnabled = store.bool(Key.voiceEnabled) ?? true
        liveVoiceEnabled = store.bool(Key.liveVoiceEnabled) ?? false
        liveModel = store.string(Key.liveModel) ?? "gemini-3.8-live"
        liveVoiceName = store.string(Key.liveVoiceName) ?? "Kore"
        liveIdleSeconds = store.double(Key.liveIdleSeconds) ?? 60
        pythonPath = store.string(Key.pythonPath) ?? ""
        earsScriptOverridePath = store.string(Key.earsScriptOverridePath) ?? ""
        launchAtLogin = store.bool(Key.launchAtLogin) ?? false
        notifications = store.bool(Key.notifications) ?? true
        approvalPolicy = store.string(Key.approvalPolicy)
            .flatMap(ApprovalPolicy.init(rawValue:)) ?? .ask
        lastSessionID = store.string(Key.lastSessionID) ?? ""
        promptHistory = PromptHistory(prompts: store.stringArray(Key.promptHistory) ?? [])
        terminalApp = store.string(Key.terminalApp).flatMap(TerminalPreference.init(rawValue:)) ?? .terminal
        experimentalDesktopKeys = store.bool(Key.experimentalDesktopKeys) ?? false
        speakTextAnswers = store.bool(Key.speakTextAnswers) ?? false
        micMinRMS = store.double(Key.micMinRMS) ?? 0.003
        micNoiseMultiplier = store.double(Key.micNoiseMultiplier) ?? 3.0
        micBandRatioMin = store.double(Key.micBandRatioMin) ?? 0.045
        micFlatnessMax = store.double(Key.micFlatnessMax) ?? 0.55
        micMinTonalFrames = store.int(Key.micMinTonalFrames) ?? 2
        micMinTonalFraction = store.double(Key.micMinTonalFraction) ?? 0.16
        micNoSpeechMax = store.double(Key.micNoSpeechMax) ?? 0.65
        micLogprobMin = store.double(Key.micLogprobMin) ?? -0.9
        modelCandidates = store.stringArray(Key.modelCandidates) ?? []
        showActiveModelInHUD = store.bool(Key.showActiveModelInHUD) ?? true

        // The HUD moved from a corner card to the notch silhouette. Existing installs
        // keep their old corner choice otherwise, so reset the position exactly once.
        if defaults.integer(forKey: Key.panelDesignVersion) < 1 {
            panelPosition = .notch
            defaults.set(PanelPosition.notch.rawValue, forKey: Key.panelPosition)
            defaults.set(1, forKey: Key.panelDesignVersion)
        }
    }
}
