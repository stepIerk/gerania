import Foundation

/// Side effects requested by the reducer. `AppModel` executes them.
public enum Effect: Sendable, Equatable {
    case startListening
    case stopListening
    case cancelTranscription
    case interrupt
    case stopSpeaking
    case playSound(SoundCue)
    case showPanel
    case hidePanel(after: TimeInterval)
}
