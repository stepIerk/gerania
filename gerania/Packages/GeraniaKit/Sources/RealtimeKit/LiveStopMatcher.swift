import Foundation

/// Detects the stop phrases in the input transcript of a live session.
///
/// The live mode follows the rule of the classic pipeline: «нет» and «ничего» are
/// not stop words, they are normal answers. Only an explicit phrase stops Gera.
public enum LiveStopMatcher {
    private static let fillers: Set<String> = [
        "гера", "герания", "гиро", "гира", "гэра",
        "пожалуйста", "ну", "давай", "да", "нет", "так", "все", "всё",
    ]

    private static let stops: Set<String> = [
        "стоп", "остановись", "останови", "остановить", "хватит", "замолчи", "замолкни",
        "тихо", "отмена", "отмени", "отменить", "пока", "прощай", "закончи",
        "закончим", "прекрати", "стой", "отбой", "отставить", "забудь",
    ]

    private static let phrases: Set<String> = [
        "не надо", "до свидания", "все хватит",
    ]

    /// Whether the whole phrase is a stop command.
    public static func isStop(_ text: String) -> Bool {
        let tokens = normalize(text)
        guard !tokens.isEmpty else {
            return false
        }
        let meaningful = tokens.filter { !fillers.contains($0) }
        guard !meaningful.isEmpty else {
            return false
        }
        let phrase = meaningful.joined(separator: " ")
        if phrases.contains(phrase) {
            return true
        }
        return meaningful.allSatisfy { stops.contains($0) }
    }

    /// Splits the phrase into normalized words.
    static func normalize(_ text: String) -> [String] {
        text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
