import Foundation
import GeraniaCore
import Testing

@Suite("SpeechTextCleaner")
struct SpeechTextCleanerTests {
    @Test("Обычный текст не меняется")
    func plainText() {
        #expect(SpeechTextCleaner.clean("Просто текст") == "Просто текст")
    }

    @Test("Блок кода удаляется")
    func codeBlockIsRemoved() {
        let text = "До кода.\n```swift\nlet a = 1\n```\nПосле кода."

        let result = SpeechTextCleaner.clean(text)

        #expect(!result.contains("let a"))
        #expect(result.contains("До кода"))
        #expect(result.contains("После кода"))
    }

    @Test("Инлайновый код теряет кавычки")
    func inlineCodeLosesBackticks() {
        #expect(SpeechTextCleaner.clean("Значение `x` тут") == "Значение x тут")
    }

    @Test("Ссылка сохраняет текст")
    func linkKeepsText() {
        #expect(SpeechTextCleaner.clean("Смотри [документ](https://example.com)") == "Смотри документ")
    }

    @Test("Голые ссылки удаляются")
    func bareLinkIsRemoved() {
        let result = SpeechTextCleaner.clean("Ссылка https://example.com/page тут")

        #expect(!result.contains("https"))
        #expect(result.contains("Ссылка"))
    }

    @Test("Markdown-метки убираются")
    func markdownMarksAreRemoved() {
        let result = SpeechTextCleaner.clean("**Жирный** _курсив_ # заголовок")

        #expect(!result.contains("*"))
        #expect(!result.contains("_"))
        #expect(!result.contains("#"))
    }

    @Test("Пробелы схлопываются")
    func spacesAreCollapsed() {
        #expect(SpeechTextCleaner.clean("Много   пробелов\n\nи перенос") == "Много пробелов и перенос")
    }

    @Test("Длинный текст режется по последней фразе")
    func longTextIsCut() {
        let sentence = "Это предложение достаточно длинное для проверки. "
        let text = String(repeating: sentence, count: 40)

        let result = SpeechTextCleaner.clean(text, limit: 200)

        #expect(result.count <= 200)
        #expect(result.hasSuffix("."))
    }

    @Test("Обрезка без фразы режет по символам")
    func longTextWithoutSentence() {
        let text = String(repeating: "а", count: 600)

        let result = SpeechTextCleaner.clean(text, limit: 100)

        #expect(result.count == 100)
    }

    @Test("Лимит не трогает короткий текст")
    func shortTextIsKept() {
        #expect(SpeechTextCleaner.clean("Коротко", limit: 500) == "Коротко")
    }
}
