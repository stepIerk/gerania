import Foundation

/// Collects the user's phrases of one live turn and decides whether it was a
/// farewell.
///
/// Gemini sends the input transcription in chunks, so the decision is made at
/// `turnComplete`, when the whole phrase is known. The text is capped: only the
/// tail matters, and the buffer must not grow for the whole session.
public struct LiveEndDetector: Sendable {
    private static let limit = 300

    private var text = ""

    public init() {}

    /// Remembers a chunk of the user's speech.
    public mutating func addUser(_ chunk: String) {
        let value = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        text = text.isEmpty ? value : text + " " + value
        if text.count > Self.limit {
            text = String(text.suffix(Self.limit))
        }
    }

    /// Whether the finished turn was a farewell; resets the collected text.
    public mutating func finishTurn() -> Bool {
        defer { text = "" }
        return LiveEndMatcher.isEnd(text)
    }

    /// Forgets the current turn.
    public mutating func reset() {
        text = ""
    }

    /// The text collected for the current turn.
    public var currentText: String {
        text
    }
}
