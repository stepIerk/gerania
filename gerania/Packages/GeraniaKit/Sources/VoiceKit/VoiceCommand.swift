import Foundation

/// Command sent to the voice front-end.
public enum VoiceCommand: Sendable, Equatable {
    /// The application state: the agent works, the speech plays.
    case state(busy: Bool, speaking: Bool)
    /// Do not listen for the given time (after the sounds of the app).
    ///
    /// `keepPhrase` keeps the current utterance alive: the frames of our own
    /// sound are skipped, but the phrase is not reset. Without it a cue that
    /// plays in the middle of a command would cut the command.
    case mute(seconds: Double, keepPhrase: Bool = true)
    /// Wait for a command without the wake word.
    case arm
    /// Stop waiting for a command.
    case disarm
    /// Start sending the microphone level.
    case levelsOn
    /// Stop sending the microphone level.
    case levelsOff
    /// Override the thresholds.
    case config(values: [String: Double])
    /// Release the microphone for a live session.
    case suspend
    /// Take the microphone back after a live session.
    case resume
    /// Finish the script.
    case shutdown

    /// JSON line for the stdin of the script.
    public var payload: String {
        switch self {
        case let .state(busy, speaking):
            Self.encode(["type": "state", "busy": busy, "speaking": speaking])
        case let .mute(seconds, keepPhrase):
            Self.encode(["type": "mute", "sec": seconds, "keep_phrase": keepPhrase])
        case .arm:
            Self.encode(["type": "arm"])
        case .disarm:
            Self.encode(["type": "disarm"])
        case .levelsOn:
            Self.encode(["type": "levels_on"])
        case .levelsOff:
            Self.encode(["type": "levels_off"])
        case let .config(values):
            Self.encode(["type": "config", "values": values])
        case .suspend:
            Self.encode(["type": "suspend"])
        case .resume:
            Self.encode(["type": "resume"])
        case .shutdown:
            Self.encode(["type": "shutdown"])
        }
    }

    private static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }
}
