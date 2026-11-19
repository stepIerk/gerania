import Foundation
import GeraniaCore
import Observation
import VoiceKit

/// State of the microphone input that the settings show and the hotkeys change.
///
/// Settings are `VoiceInputSettings`; this object adds what the ears reported
/// (which detectors run), the recording of the owner voice and the hotkey state.
@MainActor
@Observable
public final class VoiceInputController {
    public let settings: VoiceInputSettings

    /// Porcupine runs: «Гера» is caught by the detector, not by Whisper.
    public private(set) var keywordActive = false
    public private(set) var keywordDetail = "ещё не запускался"
    /// Eagle runs with the recorded owner profile.
    public private(set) var ownerActive = false
    public private(set) var ownerDetail = "ещё не запускался"

    /// Recording of the owner voice: `nil` when idle, 0…100 while recording.
    public internal(set) var enrollPercent: Double?
    public internal(set) var enrollMessage: String?

    /// When the talk hotkey went down; `nil` when it is up.
    @ObservationIgnored var talkPressedAt: Date?
    /// A tap of the talk hotkey in the push-to-talk live dialog opens the
    /// microphone until the next tap.
    @ObservationIgnored var liveTalkLatched = false
    /// Someone else (or Gera's own voice) talks during the live dialog.
    @ObservationIgnored var liveOtherSpeaking = false
    @ObservationIgnored var enrollment: VoiceEnrollment?

    /// Holding the key longer than this is «hold to talk»; shorter is a tap.
    static let holdThreshold: TimeInterval = 0.35

    public init(settings: VoiceInputSettings = VoiceInputSettings()) {
        self.settings = settings
    }

    func noteEngines(keyword: Bool, keywordDetail: String, owner: Bool, ownerDetail: String) {
        keywordActive = keyword
        self.keywordDetail = keywordDetail
        ownerActive = owner
        self.ownerDetail = ownerDetail
    }

    /// The owner gate is on and the ears really check the voice.
    var ownerGateActive: Bool {
        settings.ownerGateEnabled && ownerActive
    }
}

/// Whether the live dialog may send the microphone to Gemini right now.
///
/// Pure function: the tests cover every mode without audio.
enum LiveInputPolicy {
    static func isOpen(
        mode: ListenMode,
        modelSpeaking: Bool,
        talkHeld: Bool,
        talkLatched: Bool,
        otherSpeaking: Bool
    ) -> Bool {
        if otherSpeaking, !talkHeld {
            return false
        }
        switch mode {
        case .always:
            return true
        case .notWhileAnswering:
            return !modelSpeaking || talkHeld
        case .pushToTalk:
            return talkHeld || talkLatched
        }
    }
}
