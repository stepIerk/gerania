import AVFoundation
import Foundation
import GeraniaCore

/// Plays the short earcons of the application.
///
/// The cues are synthesized by `SoundCueSynthesizer` and played through one
/// `AVAudioEngine` node: a new cue replaces the previous one, exactly like the
/// earcons of a smart speaker. Before a cue the microphone is soft-muted, but
/// the voice front-end keeps the current phrase alive, so a cue that lands in
/// the middle of a command does not cut it.
@MainActor
public final class SoundPlayer {
    /// Called before a cue: the voice script must skip its own sound.
    ///
    /// The value is the length of the cue plus a small margin.
    public var onMute: ((Double) -> Void)?
    /// Whether the cues are played at all.
    public var isEnabled = true
    /// Volume of the cues relative to the system volume.
    public var volume: Float = 1 {
        didSet { player.volume = volume }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [SoundCue: AVAudioPCMBuffer] = [:]
    private var lastCue: (cue: SoundCue, at: Date)?

    public init() {
        engine.attach(player)
        let format = AVAudioFormat(
            standardFormatWithSampleRate: SoundCueSynthesizer.sampleRate,
            channels: 1
        )
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.volume = volume
    }

    /// Plays the cue, replacing the previous one.
    public func play(_ cue: SoundCue) {
        guard isEnabled else { return }
        let now = Date()
        // The same cue twice in a row is a duplicate event, not a new state.
        if let lastCue, lastCue.cue == cue, now.timeIntervalSince(lastCue.at) < 0.18 {
            return
        }
        lastCue = (cue, now)
        guard let buffer = buffer(for: cue) else { return }
        if cue.muteDuration > 0 {
            onMute?(cue.muteDuration)
        }
        do {
            try startEngineIfNeeded()
        } catch {
            Log.voice
                .error("cannot start the sound engine: \(error.localizedDescription, privacy: .public)")
            return
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }

    /// Stops the current cue.
    public func stopAll() {
        player.stop()
    }

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    private func buffer(for cue: SoundCue) -> AVAudioPCMBuffer? {
        if let cached = buffers[cue] {
            return cached
        }
        let samples = SoundCueSynthesizer.samples(for: cue)
        guard let format = AVAudioFormat(
                  standardFormatWithSampleRate: SoundCueSynthesizer.sampleRate,
                  channels: 1
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0]
        else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        buffers[cue] = buffer
        return buffer
    }
}
