import Foundation

/// Cleans a markdown answer before it is spoken.
///
/// The rules repeat the `clean_for_speech` of the legacy voice front-end: code blocks
/// disappear, inline code loses its backticks, links keep their text, bare links and
/// markdown marks are dropped.
public enum SpeechTextCleaner {
    /// Maximum number of characters of the spoken text.
    public static let defaultLimit = 500

    /// Returns the text ready for the speech synthesizer.
    public static func clean(_ text: String, limit: Int = defaultLimit) -> String {
        var result = text
        result = replace(pattern: "```[\\s\\S]*?```", in: result, with: " ")
        result = replace(pattern: "`([^`]*)`", in: result, with: "$1")
        result = replace(pattern: "\\[([^\\]]+)\\]\\([^)]+\\)", in: result, with: "$1")
        result = replace(pattern: "https?://\\S+", in: result, with: " ")
        result = replace(pattern: "[*#_>|~]", in: result, with: " ")
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return truncate(result, limit: limit)
    }

    /// Cuts the text at the last complete sentence, if there is one.
    public static func truncate(_ text: String, limit: Int) -> String {
        guard limit > 0, text.count > limit else { return text }
        let cut = String(text.prefix(limit))
        let ends: [Character] = [".", "!", "?"]
        if let index = cut.lastIndex(where: { ends.contains($0) }), cut.distance(from: cut.startIndex, to: index) > 80 {
            return String(cut[...index])
        }
        return cut
    }

    private static func replace(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
