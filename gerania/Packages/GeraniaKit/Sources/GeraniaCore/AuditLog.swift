import Foundation

/// One line of the action journal.
///
/// The journal answers «what did Gerania do on my Mac»: which tool ran, with
/// which argument, how it ended. It is written as JSONL so the file stays
/// readable, grep-able and append-only.
public struct AuditEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    /// Technical name: `web_search`, `computer_use`, `approval`.
    public let tool: String
    /// Short argument: a query, a command, a URL, a file path.
    public let detail: String?
    /// `auto`, `computer`, an approval choice (`once`, `deny`) or `answered`.
    public let decision: String
    /// Whether the call succeeded; `nil` while the decision is unknown.
    public let ok: Bool?
    /// Short result: a count of pages, a page title, an exit code.
    public let summary: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        tool: String,
        detail: String? = nil,
        decision: String = "auto",
        ok: Bool? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.date = date
        self.tool = tool
        self.detail = detail
        self.decision = decision
        self.ok = ok
        self.summary = summary
    }
}

/// Append-only JSONL journal in `~/Library/Application Support/Gerania/audit.jsonl`.
public actor AuditLog {
    public nonisolated let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL? = nil) {
        self.url = url ?? AuditLog.defaultURL()
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// The journal next to the voice environment of the app.
    public nonisolated static func defaultURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Gerania", isDirectory: true)
            .appendingPathComponent("audit.jsonl")
    }

    /// Appends one record. A broken journal never breaks a turn.
    public func append(_ entry: AuditEntry) {
        do {
            try prepareDirectory()
            let line = try encoder.encode(entry)
            var data = line
            data.append(0x0A)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            Log.hermes.error("audit append failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The newest `limit` records, oldest first. Malformed lines are skipped:
    /// the journal is append-only and a crash may leave a partial tail.
    public func recent(limit: Int = 50) -> [AuditEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        let selected = lines.suffix(max(0, limit))
        return selected.compactMap { line in
            try? decoder.decode(AuditEntry.self, from: Data(line))
        }
    }

    /// Erases the journal.
    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Hides obvious secrets in the argument before it reaches the disk.
    public nonisolated static func redacted(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        var value = text
        let rules = [
            (#"(?i)bearer\s+\S+"#, "Bearer ***"),
            (#"(?i)\b(api[_-]?key|token|secret|password|authorization)\b\s*[:=]\s*(?!(?:\*|bearer\b))\S+"#, "$1=***"),
        ]
        for (pattern, replacement) in rules {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > 300 ? String(collapsed.prefix(299)) + "…" : collapsed
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
