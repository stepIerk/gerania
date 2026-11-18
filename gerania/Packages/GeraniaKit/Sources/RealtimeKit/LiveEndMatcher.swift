import Foundation

/// Detects farewells that end the live dialog politely.
///
/// Unlike `LiveStopMatcher`, a farewell does not cut Gera off: she answers, says
/// goodbye and the application closes the session when the speech is over. Only
/// a phrase made entirely of closing words counts, so «спасибо, а теперь открой
/// Safari» keeps the dialog open. Words are normalized like in `LiveStopMatcher`:
/// lower case, «ё» → «е», punctuation removed.
public enum LiveEndMatcher {
    /// Address words and politeness that do not change the meaning.
    private static let fillers: Set<String> = [
        "гера", "герания", "гиро", "гира", "гэра",
        "ну", "да", "нет", "так", "ок", "окей", "хорошо", "ладно",
        "пожалуйста", "тебе", "вам", "большое", "огромное",
    ]

    /// Strong closing words: their presence makes a short phrase a goodbye.
    private static let closers: Set<String> = [
        "спасибо", "благодарю", "пока", "прощай", "прощайте",
    ]

    /// Glue words that may surround a strong closing word.
    private static let glue: Set<String> = [
        "за", "помощь", "что", "помогла", "помог", "помогли",
        "все", "это", "на", "этом", "больше", "ничего", "не", "нужно", "надо",
    ]

    /// Farewells without a strong closing word: they are matched exactly.
    private static let exact: Set<String> = [
        "это все", "на этом все", "все на этом",
        "больше ничего", "больше не нужно", "мне больше не нужно",
        "больше ничего не нужно", "ничего больше не нужно", "мне больше ничего не нужно",
        "ничего больше",
        "до свидания", "до встречи", "спокойной ночи",
        "закончили", "на этом закончим", "все закончили",
    ]

    /// The whole phrase must be one of the closing phrases.
    public static func isEnd(_ text: String) -> Bool {
        let tokens = LiveStopMatcher.normalize(text)
        guard !tokens.isEmpty else {
            return false
        }
        // «Пока не надо», «пока нет», «пока что» mean "not yet", not goodbye.
        let raw = tokens.joined(separator: " ")
        if raw == "пока нет" || raw == "пока ничего" || raw == "пока что" {
            return false
        }
        if raw.hasPrefix("пока не ") || raw.hasPrefix("пока что ") {
            return false
        }
        let meaningful = tokens.filter { !fillers.contains($0) }
        guard !meaningful.isEmpty else {
            return false
        }
        let phrase = meaningful.joined(separator: " ")
        if exact.contains(phrase) {
            return true
        }
        guard meaningful.contains(where: closers.contains) else {
            return false
        }
        return meaningful.allSatisfy { closers.contains($0) || glue.contains($0) }
    }
}
