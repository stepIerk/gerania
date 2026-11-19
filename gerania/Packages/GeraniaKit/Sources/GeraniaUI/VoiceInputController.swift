import Foundation
import GeraniaCore
import Observation
import VoiceKit

/// State of the microphone input that the settings show and the hotkeys change.
///
/// Settings are `VoiceInputSettings`; this object adds what the ears reported
/// (what catches «Гера», what tells speech from noise) and the hotkey state.
@MainActor
@Observable
public final class VoiceInputController {
    public let settings: VoiceInputSettings

    /// What catches «Гера»: «Whisper» or «своя модель: …», with the reason of a fallback.
    public private(set) var wakeDetail = "ещё не запускался"
    /// A custom wake model runs: Whisper starts only after the wake word.
    public private(set) var keywordActive = false
    /// `silero` or `spectral`; empty until the ears start.
    public private(set) var speechDetector = ""
    public private(set) var speechDetail = "ещё не запускался"

    /// When the talk hotkey went down; `nil` when it is up.
    @ObservationIgnored var talkPressedAt: Date?
    /// A tap of the talk hotkey in the push-to-talk live dialog opens the
    /// microphone until the next tap.
    @ObservationIgnored var liveTalkLatched = false

    /// Holding the key longer than this is «hold to talk»; shorter is a tap.
    static let holdThreshold: TimeInterval = 0.35

    public init(settings: VoiceInputSettings = VoiceInputSettings()) {
        self.settings = settings
    }

    func noteEngines(wake: String, keyword: Bool, speech: String, speechDetail: String) {
        wakeDetail = wake
        keywordActive = keyword
        speechDetector = speech
        self.speechDetail = speechDetail
    }

    /// Silero runs: the best protection from music, TV and typing.
    public var usesNeuralVAD: Bool {
        speechDetector == "silero"
    }
}

/// Whether the live dialog may send the microphone to Gemini right now.
///
/// Pure function: the tests cover every mode without audio.
enum LiveInputPolicy {
    static func isOpen(mode: ListenMode, modelSpeaking: Bool, talkHeld: Bool, talkLatched: Bool) -> Bool {
        switch mode {
        case .always:
            true
        case .notWhileAnswering:
            !modelSpeaking || talkHeld
        case .pushToTalk:
            talkHeld || talkLatched
        }
    }
}
