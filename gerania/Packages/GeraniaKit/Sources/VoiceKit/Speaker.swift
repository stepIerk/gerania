import AVFoundation
import Foundation
import GeraniaCore

/// Speaks the answer while it streams.
///
/// The text is cut into sentences by `SentenceChunker` and queued as utterances, so the
/// first sentence is spoken long before the answer is finished.
@MainActor
public final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    /// Settings of the speech.
    public struct Settings: Sendable {
        /// Name of the voice, for example «Milena».
        public var voiceName: String
        /// Speed of the speech.
        public var rate: Double
        /// Maximum number of characters to speak.
        public var maxCharacters: Int
        /// Whether the answers are spoken at all.
        public var isEnabled: Bool

        public init(
            voiceName: String = "Milena",
            rate: Double = 0.5,
            maxCharacters: Int = 500,
            isEnabled: Bool = true
        ) {
            self.voiceName = voiceName
            self.rate = rate
            self.maxCharacters = maxCharacters
            self.isEnabled = isEnabled
        }
    }

    /// Called when the speech starts or stops.
    public var onSpeakingChanged: ((Bool) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var chunker = SentenceChunker()
    private var settings = Settings()
    private var spokenCharacters = 0
    private var didReachLimit = false
    private var voice: AVSpeechSynthesisVoice?

    override public init() {
        super.init()
        synthesizer.delegate = self
        voice = Self.pickVoice(named: settings.voiceName)
    }

    /// Applies the settings of the application.
    public func apply(_ settings: Settings) {
        self.settings = settings
        if voice == nil || Self.pickVoice(named: settings.voiceName)?.identifier != voice?.identifier {
            voice = Self.pickVoice(named: settings.voiceName)
        }
    }

    /// Whether the synthesizer is speaking right now.
    public var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    /// Adds a piece of the answer to the speech.
    public func feed(_ delta: String) {
        guard settings.isEnabled, !didReachLimit else { return }
        for sentence in chunker.feed(delta) {
            speak(sentence)
        }
    }

    /// Speaks the rest of the answer.
    public func finish() {
        guard settings.isEnabled else { return }
        if let rest = chunker.flush() {
            speak(rest)
        }
    }

    /// Speaks a short phrase right away.
    public func speakNow(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Float(settings.rate)
        synthesizer.speak(utterance)
    }

    /// Stops the speech and clears the queue.
    public func stop() {
        chunker.reset()
        spokenCharacters = 0
        didReachLimit = false
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        MainActor.assumeIsolated {
            self.onSpeakingChanged?(true)
        }
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        MainActor.assumeIsolated {
            if !self.synthesizer.isSpeaking {
                self.onSpeakingChanged?(false)
            }
        }
    }

    private func speak(_ sentence: String) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if spokenCharacters + trimmed.count > settings.maxCharacters {
            didReachLimit = true
            let limit = AVSpeechUtterance(string: "Подробности на экране.")
            limit.voice = voice
            limit.rate = Float(settings.rate)
            synthesizer.speak(limit)
            spokenCharacters += limit.speechString.count
            return
        }
        spokenCharacters += trimmed.count
        guard let voice else {
            speakWithSay(trimmed)
            return
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = Float(settings.rate)
        synthesizer.speak(utterance)
    }

    /// Fallback for the systems without the Russian voice.
    private func speakWithSay(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-r", "190", "-f", "-"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let input = Pipe()
        process.standardInput = input
        do {
            try process.run()
            try? input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
            try? input.fileHandleForWriting.close()
        } catch {
            Log.voice.error("cannot run say: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Finds the voice by name, preferring the best quality.
    static func pickVoice(named name: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ru") }
        guard !voices.isEmpty else { return nil }
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return voices.first }
        let matching = voices.filter { $0.name.lowercased().contains(wanted) }
        guard !matching.isEmpty else { return voices.first }
        if let voice = matching.first(where: { $0.quality == .premium }) {
            return voice
        }
        if let voice = matching.first(where: { $0.quality == .enhanced }) {
            return voice
        }
        return matching.first
    }
}
