import Foundation

/// One parsed memory file: entries, its budget and the fingerprint of the read.
///
/// Mutations are pure: they return a new document or throw. The store writes the
/// new document under a lock, so the format and the limit are checked in one place.
public struct MemoryDocument: Sendable, Equatable {
    public let kind: MemoryKind
    public let url: URL
    public let limit: Int
    public let entries: [String]
    /// State of the file when it was read; a save must see the same state.
    public let fingerprint: MemoryFingerprint

    public init(
        kind: MemoryKind,
        url: URL,
        limit: Int? = nil,
        entries: [String],
        fingerprint: MemoryFingerprint
    ) {
        self.kind = kind
        self.url = url
        self.limit = limit ?? kind.limit
        self.entries = entries
        self.fingerprint = fingerprint
    }

    /// Parses the raw file. A missing file is an empty document.
    public static func parse(
        kind: MemoryKind,
        url: URL,
        raw: String,
        limit: Int? = nil,
        fingerprint: MemoryFingerprint
    ) -> MemoryDocument {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let entries = normalized
            .components(separatedBy: MemoryKind.delimiter)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return MemoryDocument(
            kind: kind,
            url: url,
            limit: limit,
            entries: entries,
            fingerprint: fingerprint
        )
    }

    /// Length of the file as Hermes counts it: entries joined by the delimiter.
    public var characters: Int {
        joined.unicodeScalars.count
    }

    public var remaining: Int {
        max(0, limit - characters)
    }

    public var isOverLimit: Bool {
        characters > limit
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// «3 записи» for the column header.
    public var countText: String {
        "\(entries.count) \(Self.plural(entries.count, "запись", "записи", "записей"))"
    }

    /// Appends one entry at the end.
    public func adding(_ text: String) throws -> MemoryDocument {
        try adding(contentsOf: [text])
    }

    /// Appends several entries at once: one check of the budget, one write.
    public func adding(contentsOf texts: [String]) throws -> MemoryDocument {
        var updated = entries
        for text in texts {
            let entry = try Self.validated(text)
            updated.append(entry)
        }
        return try replacingEntries(updated)
    }

    /// Replaces one entry, usually from the editor sheet.
    public func replacing(at index: Int, with text: String) throws -> MemoryDocument {
        guard entries.indices.contains(index) else { throw MemoryFileError.missingEntry }
        let entry = try Self.validated(text)
        var updated = entries
        updated[index] = entry
        return try replacingEntries(updated)
    }

    /// Forgets exactly one entry.
    public func removing(at index: Int) throws -> MemoryDocument {
        guard entries.indices.contains(index) else { throw MemoryFileError.missingEntry }
        var updated = entries
        updated.remove(at: index)
        return try replacingEntries(updated)
    }

    /// Forgets everything.
    public func cleared() -> MemoryDocument {
        MemoryDocument(
            kind: kind,
            url: url,
            limit: limit,
            entries: [],
            fingerprint: fingerprint
        )
    }

    /// The file content for the next atomic write.
    public var serialized: String {
        joined
    }

    private var joined: String {
        entries.joined(separator: MemoryKind.delimiter)
    }

    private func replacingEntries(_ updated: [String]) throws -> MemoryDocument {
        let content = updated.joined(separator: MemoryKind.delimiter)
        let characters = content.unicodeScalars.count
        guard characters <= limit else {
            throw MemoryFileError.overLimit(kind: kind, limit: limit, characters: characters)
        }
        return MemoryDocument(
            kind: kind,
            url: url,
            limit: limit,
            entries: updated,
            fingerprint: fingerprint
        )
    }

    /// Trims the text and rejects entries that would break the `§` format.
    private static func validated(_ text: String) throws -> String {
        let entry = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { throw MemoryFileError.emptyEntry }
        let hasDelimiterLine = entry
            .components(separatedBy: "\n")
            .contains { $0.trimmingCharacters(in: .whitespaces) == "§" }
        guard !hasDelimiterLine else { throw MemoryFileError.delimiterInEntry }
        return entry
    }

    private static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let tail = count % 100
        if (11 ... 14).contains(tail) {
            return many
        }
        return switch count % 10 {
        case 1: one
        case 2 ... 4: few
        default: many
        }
    }
}
