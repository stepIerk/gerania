import Foundation

/// Renders the memory files exactly like Hermes injects them into a session.
///
/// Hermes builds a block from the entries joined by `\n§\n`:
///
/// ```
/// ══════════════════════════════════════════════
/// USER PROFILE (who the user is) [42% — 580/1,375 chars]
/// ══════════════════════════════════════════════
/// Обращаться: Степан.
/// §
/// Город: Москва. Часовой пояс: Europe/Moscow.
/// ```
///
/// The settings tab shows the same text, so «что Геря узнает в новой сессии»
/// matches the real system prompt instead of a hand-made summary.
public enum MemoryBlockFormatter {
    /// The 46-character rule Hermes puts above and below the title.
    public static let separator = String(repeating: "═", count: 46)

    /// The title Hermes uses for the block.
    public static func title(for kind: MemoryKind) -> String {
        switch kind {
        case .user: "USER PROFILE (who the user is)"
        case .notes: "MEMORY (your personal notes)"
        }
    }

    /// «42% — 580/1,375 chars», the usage line Hermes puts in the title.
    public static func usage(for document: MemoryDocument) -> String {
        let percent = document.limit > 0
            ? min(100, document.characters * 100 / document.limit)
            : 0
        return "\(percent)% — \(grouped(document.characters))/\(grouped(document.limit)) chars"
    }

    /// The block Hermes would inject; empty for an empty file.
    public static func block(for document: MemoryDocument) -> String {
        guard !document.isEmpty else { return "" }
        return block(for: document, body: document.serialized)
    }

    /// The block for the settings preview: the header is always visible so the
    /// person sees the budget even before the first entry exists.
    public static func preview(for document: MemoryDocument) -> String {
        let body = document.isEmpty ? "— пусто: в системный промпт не попадает —" : document.serialized
        return block(for: document, body: body)
    }

    private static func block(for document: MemoryDocument, body: String) -> String {
        let header = title(for: document.kind)
        return [
            separator,
            "\(header) [\(usage(for: document))]",
            separator,
            body,
        ].joined(separator: "\n")
    }

    /// Groups an integer with commas the way Hermes formats `f"{value:,}"`.
    public static func grouped(_ value: Int) -> String {
        let digits = Array(String(value))
        var result = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0, (digits.count - offset).isMultiple(of: 3) {
                result.append(",")
            }
            result.append(digit)
        }
        return result
    }
}
