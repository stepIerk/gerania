@testable import GeraniaCore
import Testing

@Suite("Sound cues")
struct SoundCueSynthesizerTests {
    /// Length of the cue in seconds.
    private func duration(_ cue: SoundCue) -> Double {
        Double(SoundCueSynthesizer.samples(for: cue).count) / SoundCueSynthesizer.sampleRate
    }

    @Test("Every cue is shorter than 300 ms")
    func shortCues() {
        for cue in SoundCue.allCases {
            let length = duration(cue)
            #expect(length > 0.03, "\(cue) is too short: \(length) s")
            #expect(length <= 0.35, "\(cue) is too long: \(length) s")
        }
    }

    @Test("Cues are quieter than speech and never clip")
    func quietCues() {
        for cue in SoundCue.allCases {
            let samples = SoundCueSynthesizer.samples(for: cue)
            let peak = samples.map { abs($0) }.max() ?? 0
            #expect(peak <= 0.2, "\(cue) peaks at \(peak)")
            #expect(peak > 0.01, "\(cue) is silent")
            #expect(!samples.contains { $0.isNaN || $0.isInfinite })
        }
    }

    @Test("Cues start and end near silence: no clicks")
    func softEdges() {
        for cue in SoundCue.allCases {
            let samples = SoundCueSynthesizer.samples(for: cue)
            #expect(abs(samples.first ?? 1) < 0.01, "\(cue) clicks at the start")
            #expect(abs(samples.last ?? 1) < 0.01, "\(cue) clicks at the end")
        }
    }

    @Test("Different states sound different")
    func uniqueCues() {
        let all = SoundCue.allCases.map { SoundCueSynthesizer.samples(for: $0) }
        for first in all.indices {
            for second in all.indices where second > first {
                #expect(all[first] != all[second], "two cues are identical")
            }
        }
    }

    @Test("Sample rate is honoured")
    func sampleRate() {
        let cue = SoundCue.wake
        let low = SoundCueSynthesizer.samples(for: cue, sampleRate: 22050)
        let high = SoundCueSynthesizer.samples(for: cue, sampleRate: 44100)

        #expect(low.count < high.count)
        #expect(abs(Double(low.count) / 22050 - Double(high.count) / 44100) < 0.002)
    }

    @Test("The microphone mute covers the cue and stays under a second")
    func muteCoversTheCue() {
        for cue in SoundCue.allCases {
            let mute = cue.muteDuration
            #expect(mute <= 1.0, "\(cue) mutes the microphone for too long")
            if cue == .thinking {
                // The quiet «still working» cue plays into the silence: no mute.
                #expect(mute == 0)
            } else {
                #expect(mute >= duration(cue), "\(cue) mute is shorter than the cue")
                #expect(mute <= 0.35)
            }
        }
    }
}
