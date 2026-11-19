import Foundation
import Observation

/// When Gera listens to the microphone.
public enum ListenMode: String, CaseIterable, Sendable, Identifiable {
    /// «Гера» wakes her any time; during the answer the owner can interrupt by voice.
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
            "Можно перебить ответ голосом. Чужие голоса и речь самой Геры не перебивают, "
                + "если записан ваш голос."
        case .notWhileAnswering:
            "Во время ответа микрофон глух: остановить можно сочетанием или кнопкой «Стоп»."
        case .pushToTalk:
            "Гера не слушает микрофон, пока вы не нажмёте сочетание. Удерживайте его, пока говорите, "
                + "или нажмите один раз и говорите."
        }
    }
}

/// Settings of the microphone: listen mode, wake word and owner voice.
///
/// Kept apart from `GeraSettings` so the voice input can grow without touching
/// the main settings type.
@MainActor
@Observable
public final class VoiceInputSettings {
    private enum Key {
        static let listenMode = "voiceListenMode"
        static let keywordSensitivity = "voiceKeywordSensitivity"
        static let ownerGateEnabled = "voiceOwnerGateEnabled"
        static let ownerThreshold = "voiceOwnerThreshold"
    }

    @ObservationIgnored private let store: DefaultsStore

    public var listenMode: ListenMode {
        didSet { store.set(listenMode.rawValue, for: Key.listenMode) }
    }

    /// Porcupine sensitivity: higher wakes easier but errs more often.
    public var keywordSensitivity: Double {
        didSet { store.set(keywordSensitivity, for: Key.keywordSensitivity) }
    }

    /// Wake words, commands and stop words count only in the owner's voice.
    public var ownerGateEnabled: Bool {
        didSet { store.set(ownerGateEnabled, for: Key.ownerGateEnabled) }
    }

    /// Eagle score above which the voice is the owner's.
    public var ownerThreshold: Double {
        didSet { store.set(ownerThreshold, for: Key.ownerThreshold) }
    }

    public init(defaults: UserDefaults = .standard) {
        store = DefaultsStore(defaults: defaults)
        listenMode = store.string(Key.listenMode).flatMap(ListenMode.init(rawValue:)) ?? .always
        keywordSensitivity = store.double(Key.keywordSensitivity) ?? 0.6
        ownerGateEnabled = store.bool(Key.ownerGateEnabled) ?? true
        ownerThreshold = store.double(Key.ownerThreshold) ?? 0.5
    }
}
