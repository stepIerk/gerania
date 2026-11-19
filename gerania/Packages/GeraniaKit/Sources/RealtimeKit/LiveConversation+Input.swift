import Foundation
import GeraniaCore

/// What the person controls while the live dialog runs: the microphone gate
/// and «stop the answer».
public extension LiveConversation {
    /// Opens or closes the microphone for Gemini (listen mode, hotkey, owner gate).
    /// A closed gate sends silence, so Gemini's own VAD still ends the turn.
    func setInputGate(open: Bool) {
        audio.setInputGateOpen(open)
    }

    /// Silences the current answer at once and skips the rest of its audio; the
    /// dialog stays open and the microphone listens.
    func interruptSpeech() {
        droppingAnswer = true
        audio.stopPlayback()
        noteActivity()
        Log.voice.notice("live: answer interrupted by the user")
    }
}
