import Foundation

/// Builds the short earcons of the assistant.
///
/// The cues are synthesized instead of using the system sounds: the system
/// sounds last 0.4–0.5 s and are loud, so they had to be covered by a long
/// microphone mute. The synthesized cues are 55–300 ms and quiet, and the
/// envelope has no clicks at the edges.
///
/// The set follows the Alexa design rules: a cue is shorter than 300 ms, is
/// quieter than speech, and one sound means exactly one state.
public enum SoundCueSynthesizer {
    /// Sample rate of the generated cues.
    public static let sampleRate: Double = 44100
    /// Peak amplitude: about −15 dBFS, deliberately below speech.
    static let peak: Double = 0.18
    /// Length of the attack, seconds: removes the click at the start.
    static let attack: Double = 0.006
    /// Length of the release, seconds: removes the click at the end.
    static let release: Double = 0.03

    /// One note of a cue.
    struct Note {
        let frequency: Double
        let duration: Double
        let level: Double
    }

    /// The motif of every cue.
    static func notes(for cue: SoundCue) -> [Note] {
        switch cue {
        case .wake:
            // Ready to listen: a rising major third.
            [
                Note(frequency: 1046.50, duration: 0.075, level: 0.85),
                Note(frequency: 1318.51, duration: 0.115, level: 1.0),
            ]
        case .sent:
            // Request accepted: one soft tick.
            [Note(frequency: 1567.98, duration: 0.055, level: 0.7)]
        case .thinking:
            // Still working: one low, very quiet note.
            [Note(frequency: 523.25, duration: 0.09, level: 0.45)]
        case .done:
            // Answer ready: a falling major third.
            [
                Note(frequency: 1318.51, duration: 0.08, level: 0.9),
                Note(frequency: 1046.50, duration: 0.14, level: 0.8),
            ]
        case .error:
            // Failure: a falling minor third.
            [
                Note(frequency: 440.00, duration: 0.11, level: 0.85),
                Note(frequency: 349.23, duration: 0.19, level: 0.85),
            ]
        case .stop:
            // Stopped: a short low blip.
            [Note(frequency: 587.33, duration: 0.085, level: 0.75)]
        }
    }

    /// PCM samples of the cue, mono, in −1…1.
    public static func samples(
        for cue: SoundCue,
        sampleRate: Double = SoundCueSynthesizer.sampleRate
    ) -> [Float] {
        var output: [Float] = []
        for note in notes(for: cue) {
            let frames = max(1, Int(note.duration * sampleRate))
            let step = 2 * Double.pi * note.frequency / sampleRate
            var phase = 0.0
            for index in 0 ..< frames {
                let time = Double(index) / sampleRate
                let progress = Double(index) / Double(frames)
                let attack = min(1, time / attack)
                let decay = exp(-3.2 * progress)
                let release = max(0, min(1, (1 - progress) * note.duration / release))
                let envelope = attack * decay * release
                // A touch of the second harmonic: less like a test tone.
                let wave = sin(phase) + 0.16 * sin(2 * phase)
                output.append(Float(wave / 1.16 * envelope * note.level * peak))
                phase += step
            }
        }
        return output
    }
}
