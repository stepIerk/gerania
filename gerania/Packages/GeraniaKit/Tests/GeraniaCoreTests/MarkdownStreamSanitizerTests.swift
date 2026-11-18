import Foundation
import GeraniaCore
import Testing

@Suite("MarkdownStreamSanitizer")
struct MarkdownStreamSanitizerTests {
    private func sanitize(_ text: String) -> String {
        MarkdownStreamSanitizer.sanitize(text)
    }

    @Test("Plain text stays untouched")
    func plainText() {
        let text = "Просто текст без разметки."
        #expect(sanitize(text) == text)
    }

    @Test("Empty text stays empty")
    func emptyText() {
        #expect(sanitize("") == "")
    }

    @Test("Closed code fence is not touched")
    func closedFence() {
        let text = "```swift\nlet a = 1\n```"
        #expect(sanitize(text) == text)
    }

    @Test("Open code fence is closed")
    func openFence() {
        let text = "```swift\nlet a = 1"
        #expect(sanitize(text) == text + "\n```")
    }

    @Test("Open tilde fence is closed with the same marker")
    func openTildeFence() {
        let text = "~~~python\nprint(1)"
        #expect(sanitize(text) == text + "\n~~~")
    }

    @Test("Unclosed bold is closed")
    func unclosedBold() {
        let text = "Это **жирный"
        #expect(sanitize(text) == text + "**")
    }

    @Test("Unclosed italic is closed")
    func unclosedItalic() {
        let text = "Это *курсив"
        #expect(sanitize(text) == text + "*")
    }

    @Test("Unclosed underscore italic is closed with an underscore")
    func unclosedUnderscore() {
        let text = "Это _курсив"
        #expect(sanitize(text) == text + "_")
    }

    @Test("Unclosed inline code is closed")
    func unclosedInlineCode() {
        let text = "Смотри `code"
        #expect(sanitize(text) == text + "`")
    }

    @Test("Finished text is not rewritten when the tail is open")
    func finishedPartIsStable() {
        let text = "Готовый **абзац**.\n\nНовый **абзац"
        let result = sanitize(text)
        #expect(result.hasPrefix("Готовый **абзац**.\n\n"))
        #expect(result == text + "**")
    }

    @Test("List markers are not treated as italic")
    func listMarkers() {
        let text = "- первый пункт\n- второй пункт"
        #expect(sanitize(text) == text)
    }

    @Test("Escaped markers are ignored")
    func escapedMarkers() {
        let text = "Звёздочка \\* и подчёркивание \\_"
        #expect(sanitize(text) == text)
    }

    @Test("Dangling table row is dropped")
    func danglingTableRow() {
        let text = """
        | Ключ | Значение |
        | --- | --- |
        | один |
        """
        let result = sanitize(text)
        #expect(!result.contains("один"))
        #expect(result.contains("| Ключ | Значение |"))
    }

    @Test("Complete table row is kept")
    func completeTableRow() {
        let text = """
        | Ключ | Значение |
        | --- | --- |
        | один | два |
        """
        #expect(sanitize(text) == text)
    }

    @Test("Inline code inside a paragraph does not close bold")
    func inlineCodeAndBold() {
        let text = "Текст с `кодом` и **жирным"
        #expect(sanitize(text) == text + "**")
    }

    @Test("Multiple paragraphs keep their code fence closed")
    func fenceInEarlierParagraph() {
        let text = "```\ncode\n```\n\nАбзац"
        #expect(sanitize(text) == text)
    }
}
