import Foundation

/// Removes keys and tokens from text that leaves the machine (diagnostic reports).
///
/// Patterns cover the shapes the providers use: Google `AIza…`, OpenAI-style
/// `sk-…`, GitHub `ghp_…`, Slack `xox…`, `Bearer …` headers, `KEY=value` lines and
/// `?key=` URL parameters. A false positive costs a few hidden characters; a
/// false negative leaks a key, so the patterns are generous.
public enum SecretRedactor {
    public static let mask = "[скрыто]"

    private static let patterns: [String] = [
        #"AIza[0-9A-Za-z_\-]{20,}"#,
        #"\b(sk|rk|pk)-[A-Za-z0-9_\-]{16,}"#,
        #"\bgh[pousr]_[A-Za-z0-9]{20,}"#,
        #"\bxox[abprs]-[A-Za-z0-9\-]{10,}"#,
        #"(?i)bearer\s+[A-Za-z0-9._\-~+/=]{12,}"#,
        #"(?i)\b([A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|TICKET)[A-Z0-9_]*)\s*[=:]\s*[^\s&]+"#,
        #"(?i)([?&](key|token|ticket|api_key)=)[^&\s]+"#,
    ]

    public static func redact(_ text: String) -> String {
        // Compiled per call: a report is built rarely, and no shared mutable state is needed.
        let expressions = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        var result = text
        for expression in expressions {
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: template(for: expression)
            )
        }
        return result
    }

    /// Keeps the name of a `KEY=value` pair and of a URL parameter, hides the value.
    private static func template(for expression: NSRegularExpression) -> String {
        if expression.pattern.contains("KEY|TOKEN") {
            return "$1=\(mask)"
        }
        if expression.pattern.contains("api_key") {
            return "$1\(mask)"
        }
        return mask
    }
}
