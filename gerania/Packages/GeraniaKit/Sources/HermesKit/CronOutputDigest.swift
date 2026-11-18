import Foundation

/// The human part of one run document from `cron/output/<job-id>/<time>.md`.
///
/// Hermes writes `# Cron Job: <name>`, metadata lines (`**Job ID:** ...`), the
/// prompt and then `## Response` with the answer. A failed run is titled
/// `# Cron Job: <id> (FAILED)`. The notification and the HUD card need only the
/// name and the answer, so everything else is dropped here.
public struct CronOutputDigest: Sendable, Equatable {
    public let title: String?
    public let body: String
    public let isFailure: Bool

    public init(title: String?, body: String, isFailure: Bool) {
        self.title = title
        self.body = body
        self.isFailure = isFailure
    }

    static let titlePrefix = "# Cron Job: "
    static let failedSuffix = " (FAILED)"
    static let responseHeading = "## Response"

    public static func parse(_ markdown: String, limit: Int = 400) -> CronOutputDigest {
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var title: String?
        var isFailure = false
        if let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true).first,
           firstLine.hasPrefix(titlePrefix)
        {
            var name = String(firstLine.dropFirst(titlePrefix.count))
                .trimmingCharacters(in: .whitespaces)
            if name.hasSuffix(failedSuffix) {
                isFailure = true
                name = String(name.dropLast(failedSuffix.count))
            }
            title = name.isEmpty ? nil : name
        }
        let body = clip(answer(in: text), limit: limit)
        return CronOutputDigest(title: title, body: body, isFailure: isFailure)
    }

    /// The text after the LAST `## Response` heading (the prompt may quote the
    /// heading itself); without it, the document minus the title and metadata.
    static func answer(in text: String) -> String {
        if let range = text.range(of: responseHeading, options: .backwards) {
            return String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                !line.hasPrefix(titlePrefix) && !(line.hasPrefix("**") && line.contains(":**"))
            }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clip(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
