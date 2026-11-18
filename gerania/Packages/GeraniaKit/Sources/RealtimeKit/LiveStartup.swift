import Foundation

/// Collects the first phrases of a live session while Gemini is connecting.
///
/// The ears keep the microphone until the user finishes the phrase: whisper
/// receives all the audio and the application transfers the complete text to
/// Gemini. The gate opens only between utterances, so a new phrase is never cut
/// in half by the handoff.
public struct LiveStartup: Sendable, Equatable {
    /// Whether the first phrase is still being collected.
    public private(set) var isTracking = false

    /// Whether the user is speaking right now.
    public private(set) var utteranceActive = false

    /// Whether the last utterance has been fully recognized.
    public private(set) var ready = false

    private var committed: [String] = []
    private var current = ""

    public init() {}

    /// Starts collecting: the seed is ignored, the first phrase is awaited.
    public mutating func begin(skipWait: Bool = false) {
        isTracking = true
        committed.removeAll()
        current = ""
        ready = skipWait
    }

    /// Stops collecting and forgets the phrase.
    public mutating func finish() {
        isTracking = false
        utteranceActive = false
        ready = false
        committed.removeAll()
        current = ""
    }

    /// Remembers the latest hypothesis of the current utterance.
    public mutating func note(_ text: String) {
        guard isTracking else {
            return
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        // The small model sometimes drops the beginning of the phrase: do not
        // replace a complete hypothesis with a shorter fragment of it.
        if !current.isEmpty, isFragment(value, of: current) {
            return
        }
        current = value
    }

    /// Whether the new hypothesis is only a part of the previous one.
    private func isFragment(_ value: String, of previous: String) -> Bool {
        let new = normalized(value)
        let old = normalized(previous)
        guard !new.isEmpty, new.count < old.count else {
            return false
        }
        return old.hasPrefix(new) || old.hasSuffix(new)
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    public mutating func utteranceStarted() {
        guard isTracking else {
            return
        }
        utteranceActive = true
        ready = false
    }

    public mutating func utteranceEnded() {
        guard isTracking else {
            return
        }
        utteranceActive = false
        let value = current
        current = ""
        if !value.isEmpty, committed.last != value {
            committed.append(value)
        }
        ready = true
    }

    /// Allows the handoff without waiting for a phrase (debug and direct start).
    public mutating func skipWait() {
        ready = true
    }

    /// Forces the handoff even if the ears have restarted and will never send
    /// `utterance_end` for the phrase collected so far.
    public mutating func forceHandoff() {
        utteranceActive = false
        ready = true
    }

    /// The microphone can be handed over right now: the phrase is complete.
    public var canHandOff: Bool {
        isTracking && ready && !utteranceActive
    }

    /// The whole collected phrase; the current hypothesis is included.
    public var transcript: String {
        let parts = current.isEmpty ? committed : committed + [current]
        return parts.joined(separator: " ")
    }

    public var isEmpty: Bool {
        transcript.isEmpty
    }
}
