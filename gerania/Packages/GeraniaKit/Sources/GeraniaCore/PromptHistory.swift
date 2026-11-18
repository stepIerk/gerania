import Foundation

/// History of the prompts the user sent.
///
/// The newest prompt is stored first, the list is limited so it never grows forever.
public struct PromptHistory: Equatable, Sendable {
    /// Maximum number of stored prompts.
    public static let limit = 50

    /// Prompts, newest first.
    public private(set) var prompts: [String]

    public init(prompts: [String] = []) {
        self.prompts = Array(prompts.prefix(Self.limit))
    }

    /// Adds a prompt to the history. Empty prompts and duplicates of the newest are ignored.
    public mutating func add(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if prompts.first == trimmed {
            return
        }
        prompts.insert(trimmed, at: 0)
        if prompts.count > Self.limit {
            prompts.removeLast(prompts.count - Self.limit)
        }
    }

    /// Removes every prompt.
    public mutating func clear() {
        prompts = []
    }

    /// The prompt before the given cursor position; `nil` cursor means the newest one.
    public func prompt(before cursor: Int?) -> (prompt: String, cursor: Int)? {
        let index = (cursor ?? -1) + 1
        guard prompts.indices.contains(index) else { return nil }
        return (prompts[index], index)
    }

    /// The prompt after the given cursor position; `nil` cursor means the oldest one.
    public func prompt(after cursor: Int?) -> (prompt: String, cursor: Int)? {
        guard let cursor, cursor > 0 else { return nil }
        return (prompts[cursor - 1], cursor - 1)
    }
}
