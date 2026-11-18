import Foundation

/// Splits a streamed answer into sentences for the speech synthesizer.
///
/// The chunker waits for a sentence boundary, ignores code blocks and tables and does not
/// cut abbreviations (`т.е.`) or numbers (`3.14`).
public struct SentenceChunker: Sendable {
    /// Minimum length of a chunk: short fragments wait for more text.
    public static let minimumLength = 24

    /// Words that end with a dot but do not end a sentence.
    public static let abbreviations: Set<String> = [
        "т.е", "и.о", "т.п", "т.д", "др", "проч", "стр", "рис", "см", "напр",
        "руб", "коп", "ул", "г", "гг", "в", "с",
    ]

    private let minimumLength: Int
    private var pending = ""
    private var speech = ""
    private var isInsideFence = false

    public init(minimumLength: Int = SentenceChunker.minimumLength) {
        self.minimumLength = minimumLength
    }

    /// Text that waits for more input.
    public var pendingText: String {
        speech + pending
    }

    /// Adds a delta and returns the finished sentences.
    public mutating func feed(_ delta: String) -> [String] {
        pending += delta
        var result: [String] = []
        while let newlineIndex = pending.firstIndex(of: "\n") {
            let line = String(pending[pending.startIndex ..< newlineIndex])
            pending.removeSubrange(pending.startIndex ... newlineIndex)
            result += consume(line: line)
        }
        return result
    }

    /// Returns the rest of the buffer as the last chunk.
    public mutating func flush() -> String? {
        var result: [String] = []
        if !pending.isEmpty {
            let line = pending
            pending = ""
            result += consume(line: line)
        }
        let rest = speech
        speech = ""
        let cleaned = SpeechTextCleaner.clean(rest)
        if !cleaned.isEmpty {
            result.append(cleaned)
        }
        guard !result.isEmpty else { return nil }
        return result.joined(separator: " ")
    }

    /// Removes everything that waits for more input.
    public mutating func reset() {
        pending = ""
        speech = ""
        isInsideFence = false
    }

    /// Adds one finished line of the answer and cuts the sentences.
    private mutating func consume(line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            isInsideFence.toggle()
            return []
        }
        if isInsideFence {
            return []
        }
        if trimmed.hasPrefix("|") {
            return []
        }

        speech += line
        speech += "\n"

        var chunks: [String] = []
        while let boundary = nextBoundary(in: speech) {
            let chunk = String(speech[speech.startIndex ..< boundary])
            speech.removeSubrange(speech.startIndex ..< boundary)
            let spoken = SpeechTextCleaner.clean(chunk)
            if !spoken.isEmpty {
                chunks.append(spoken)
            }
        }
        return chunks
    }

    /// Position right after the next sentence boundary.
    private func nextBoundary(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if ".!?…\n".contains(character) {
                var next = text.index(after: index)
                if character == "." {
                    // «прощаться...» — точка с многоточием не режет фразу трижды.
                    while next < text.endIndex, text[next] == "." {
                        next = text.index(after: next)
                    }
                }
                if text.distance(from: text.startIndex, to: next) < minimumLength {
                    index = next
                    continue
                }
                if character == ".", !isSentenceEnd(at: index, in: text) {
                    index = next
                    continue
                }
                return next
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Whether the dot at the position ends a sentence.
    private func isSentenceEnd(at index: String.Index, in text: String) -> Bool {
        let previous = text[..<index]
        let next = text.index(after: index)
        if next < text.endIndex {
            let nextCharacter = text[next]
            let previousCharacter = previous.last ?? " "
            if nextCharacter.isNumber, previousCharacter.isNumber {
                return false
            }
        }
        let word = previous
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .last
            .map { String($0).lowercased() } ?? ""
        return !Self.abbreviations.contains(word)
    }
}
