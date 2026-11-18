import AVFoundation
import Foundation

/// Converts the microphone buffer to the PCM16 format expected by Gemini.
enum LiveAudioConverter {
    struct Converted {
        let data: Data
        let level: Double
    }

    final class Box: @unchecked Sendable {
        let converter: AVAudioConverter
        let target: AVAudioFormat

        init(converter: AVAudioConverter, target: AVAudioFormat) {
            self.converter = converter
            self.target = target
        }
    }

    static func convert(_ buffer: AVAudioPCMBuffer, box: Box) -> Converted? {
        let ratio = box.target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: box.target, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var provided = false
        let status = box.converter.convert(to: output, error: &error) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error,
              output.frameLength > 0,
              let channel = output.int16ChannelData?[0]
        else {
            return nil
        }

        let data = Data(
            bytes: channel,
            count: Int(output.frameLength) * MemoryLayout<Int16>.size
        )
        return Converted(data: data, level: level(of: buffer))
    }

    static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else {
            return 0
        }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else {
            return 0
        }
        var sum: Float = 0
        for index in 0 ..< frames {
            let value = channel[index]
            sum += value * value
        }
        let rms = sqrt(sum / Float(frames))
        return Double(min(1, max(0, rms * 20)))
    }
}
