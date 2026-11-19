import Foundation
import Observation

/// When Gera listens to the microphone.
public enum ListenMode: String, CaseIterable, Sendable, Identifiable {
    /// «Гера» wakes her while she is idle; stop words work during the answer.
    case always
    /// «Гера» works while she is idle; during the answer the microphone is deaf.
    case notWhileAnswering = "not_while_answering"
    /// No wake word: only ⌃⌥G (press or hold).
    case pushToTalk = "push_to_talk"

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .always: "Всегда слушать «Гера»"
        case .notWhileAnswering: "Не слушать, пока Гера отвечает"
        case .pushToTalk: "Только по сочетанию клавиш"
        }
    }

    public var detail: String {
        switch self {
        case .always:
            "Во время ответа Гера слышит «стоп». Перебить её можно и сочетанием ⌃⌥⇧G."
        case .notWhileAnswering:
            "Во время ответа микрофон глух: остановить можно сочетанием или кнопкой «Стоп»."
        case .pushToTalk:
            "Гера не слушает микрофон, пока вы не нажмёте сочетание. Удерживайте его, пока говорите, "
                + "или нажмите один раз и говорите."
        }
    }
}

/// How hard the ears filter out noise before «Гера» may wake.
///
/// Each level is a set of thresholds for `gera_ears.py` (`config` command):
/// Whisper's confidence in the word «Гера», the frame-level speech probability
/// of Silero / the spectral detector and the share of speech in the phrase.
public enum NoiseRejection: String, CaseIterable, Sendable, Identifiable {
    case relaxed
    case normal
    case strict

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .relaxed: "Мягкая"
        case .normal: "Обычная"
        case .strict: "Строгая"
        }
    }

    public var detail: String {
        switch self {
        case .relaxed:
            "Гера слышит и тихую, неразборчивую речь, но чаще просыпается от телевизора или музыки."
        case .normal:
            "Баланс: шум, стук и музыка не будят, обычная речь работает с первого раза."
        case .strict:
            "Для шумной комнаты: «Гера» нужно сказать чётко, зато ложных срабатываний почти нет."
        }
    }

    /// Thresholds for the ears; the keys are those of `apply_config` in gera_ears.py.
    public var earsConfig: [String: Double] {
        switch self {
        case .relaxed:
            [
                "wake_min_prob": 0.3,
                "speech_prob_silero": 0.35,
                "speech_prob_spectral": 0.5,
                "partial_wake_speech_ratio": 0.25,
                "min_speech_ratio": 0.15,
            ]
        case .normal:
            [
                "wake_min_prob": 0.45,
                "speech_prob_silero": 0.5,
                "speech_prob_spectral": 0.6,
                "partial_wake_speech_ratio": 0.35,
                "min_speech_ratio": 0.2,
            ]
        case .strict:
            [
                "wake_min_prob": 0.6,
                "speech_prob_silero": 0.65,
                "speech_prob_spectral": 0.8,
                "partial_wake_speech_ratio": 0.5,
                "min_speech_ratio": 0.3,
            ]
        }
    }
}

/// Settings of the microphone: listen mode, noise rejection and a custom wake model.
///
/// Kept apart from `GeraSettings` so the voice input can grow without touching
/// the main settings type.
@MainActor
@Observable
public final class VoiceInputSettings {
    private enum Key {
        static let listenMode = "voiceListenMode"
        static let noiseRejection = "voiceNoiseRejection"
        static let wakePluginPath = "voiceWakePluginPath"
    }

    @ObservationIgnored private let store: DefaultsStore

    public var listenMode: ListenMode {
        didSet { store.set(listenMode.rawValue, for: Key.listenMode) }
    }

    public var noiseRejection: NoiseRejection {
        didSet { store.set(noiseRejection.rawValue, for: Key.noiseRejection) }
    }

    /// A Python module with `create(environ)` returning a wake-word detector
    /// (`docs/VOICE_IPC.md`); empty — «Гера» is caught by Whisper.
    public var wakePluginPath: String {
        didSet { store.set(wakePluginPath, for: Key.wakePluginPath) }
    }

    public init(defaults: UserDefaults = .standard) {
        store = DefaultsStore(defaults: defaults)
        listenMode = store.string(Key.listenMode).flatMap(ListenMode.init(rawValue:)) ?? .always
        noiseRejection = store.string(Key.noiseRejection).flatMap(NoiseRejection.init(rawValue:)) ?? .normal
        wakePluginPath = store.string(Key.wakePluginPath) ?? ""
    }

    /// Environment of the ears process.
    public var earsEnvironment: [String: String] {
        let path = (wakePluginPath as NSString).expandingTildeInPath
        return path.isEmpty ? [:] : ["GERA_WAKE_PLUGIN": path]
    }
}
