import Foundation

/// Short earcons of the assistant.
///
/// One cue means one thing: the set follows the Alexa convention, so a new
/// sound never reuses the meaning of another one.
public enum SoundCue: String, Sendable, Equatable, CaseIterable {
    /// The wake word was heard: Gera listens.
    case wake
    /// The request was accepted: it goes to the agent.
    case sent
    /// The agent is still working.
    case thinking
    /// The answer is ready.
    case done
    /// Something failed.
    case error
    /// The work was stopped.
    case stop

    /// How long the microphone is soft-muted while the cue plays.
    ///
    /// The voice front-end keeps the current phrase during the mute: it only
    /// skips the frames of our own sound. The values are the length of the cue
    /// plus a small margin.
    public var muteDuration: Double {
        switch self {
        case .thinking:
            // Very quiet and played while the user is silent: no mute at all.
            0
        case .sent:
            0.10
        case .stop:
            0.13
        case .wake:
            0.23
        case .done:
            0.25
        case .error:
            0.33
        }
    }
}
