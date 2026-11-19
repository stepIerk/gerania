import Foundation

/// Event of the voice front-end (`gera_ears.py`).
///
/// The wire format is NDJSON: one JSON object per line, see `docs/VOICE_IPC.md`.
public enum VoiceEvent: Sendable, Equatable {
    /// The model is loaded, the script is ready.
    case ready(model: String)
    /// Microphone level.
    case level(rms: Double, threshold: Double, active: Bool)
    /// A phrase started.
    case utteranceStart
    /// A phrase ended.
    case utteranceEnd(duration: Double)
    /// The phrase was rejected.
    case filtered(reason: String)
    /// Recognized text.
    case transcript(text: String, noSpeech: Double, logprob: Double)
    /// The wake word was heard; the command may be in the same phrase.
    case wake(inlineCommand: String?)
    /// The text recognized while the user is still speaking.
    case partial(text: String)
    /// A command to execute.
    case command(text: String, via: CommandOrigin)
    /// The user asked to stop.
    case stop(scope: StopScope)
    /// The command did not come in time.
    case awaitTimeout
    /// The microphone was released for a live session.
    case suspended
    /// The microphone is back after a live session.
    case resumed
    /// The script failed.
    case error(message: String)
    /// The script is finishing.
    case bye
    /// Which detectors run: Porcupine for «Гера» and Eagle for the owner voice.
    case engines(keyword: Bool, keywordDetail: String, owner: Bool, ownerDetail: String)
    /// «Гера» was heard, but not in the owner's voice.
    case wakeRejected(score: Double)
    /// A command or a stop word was said by someone else.
    case speakerRejected(score: Double)
    /// Who talks while the live dialog owns the microphone.
    case speaker(SpeakerState)
    /// Recording of the owner voice: progress in percent.
    case enrollProgress(percent: Double)
    /// The owner profile is written.
    case enrollDone(path: String)

    /// Who talks during the live dialog.
    public enum SpeakerState: String, Sendable, Equatable {
        case owner
        case other
        case silence
    }

    /// Where the command came from.
    public enum CommandOrigin: String, Sendable, Equatable {
        /// The same phrase as the wake word.
        case inline
        /// A separate phrase after the wake word.
        case followup
        /// Sent while the user was still speaking, as soon as they paused.
        case partial
        /// The final transcription of the phrase: it may arrive without the wake word.
        case final
    }

    /// What the stop interrupted.
    public enum StopScope: String, Sendable, Equatable {
        /// The input was cancelled while waiting for the command.
        case input
        /// A stop word during the work or the speech.
        case busy
        /// «Гера, стоп».
        case explicit
    }

    /// Decodes one line of the IPC stream. A broken line gives `nil`.
    public static func decode(_ line: String) -> VoiceEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = payload["type"] as? String else { return nil }

        switch kind {
        case "ready":
            return .ready(model: payload["model"] as? String ?? "")
        case "level":
            return .level(
                rms: payload["rms"] as? Double ?? 0,
                threshold: payload["thr"] as? Double ?? 0,
                active: payload["active"] as? Bool ?? false
            )
        case "utterance_start":
            return .utteranceStart
        case "utterance_end":
            return .utteranceEnd(duration: payload["dur"] as? Double ?? 0)
        case "filtered":
            return .filtered(reason: payload["reason"] as? String ?? "")
        case "transcript":
            return .transcript(
                text: payload["text"] as? String ?? "",
                noSpeech: payload["no_speech"] as? Double ?? 0,
                logprob: payload["logprob"] as? Double ?? 0
            )
        case "wake":
            return .wake(inlineCommand: payload["inline_command"] as? String)
        case "partial":
            return .partial(text: payload["text"] as? String ?? "")
        case "command":
            let origin = (payload["via"] as? String).flatMap(CommandOrigin.init(rawValue:)) ?? .inline
            return .command(text: payload["text"] as? String ?? "", via: origin)
        case "stop":
            let scope = (payload["scope"] as? String).flatMap(StopScope.init(rawValue:)) ?? .busy
            return .stop(scope: scope)
        case "await_timeout":
            return .awaitTimeout
        case "suspended":
            return .suspended
        case "resumed":
            return .resumed
        case "error":
            return .error(message: payload["message"] as? String ?? "")
        case "bye":
            return .bye
        case "engines":
            return .engines(
                keyword: payload["keyword"] as? Bool ?? false,
                keywordDetail: payload["keyword_detail"] as? String ?? "",
                owner: payload["owner"] as? Bool ?? false,
                ownerDetail: payload["owner_detail"] as? String ?? ""
            )
        case "wake_rejected":
            return .wakeRejected(score: payload["score"] as? Double ?? 0)
        case "speaker_rejected":
            return .speakerRejected(score: payload["score"] as? Double ?? 0)
        case "speaker":
            return (payload["who"] as? String).flatMap(SpeakerState.init(rawValue:)).map { VoiceEvent.speaker($0) }
        case "enroll_progress":
            return .enrollProgress(percent: payload["percent"] as? Double ?? 0)
        case "enroll_done":
            return .enrollDone(path: payload["path"] as? String ?? "")
        default:
            return nil
        }
    }
}
