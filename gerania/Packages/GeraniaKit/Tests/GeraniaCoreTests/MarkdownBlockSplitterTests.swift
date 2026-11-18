import Foundation
import GeraniaCore
import Testing

@Suite("MarkdownBlockSplitter")
struct MarkdownBlockSplitterTests {
    @Test("Empty text has no blocks")
    func emptyText() {
        let split = MarkdownBlockSplitter.split("")
        #expect(split.completed.isEmpty)
        #expect(split.tail.isEmpty)
    }

    @Test("Text without an empty line is one tail block")
    func singleParagraph() {
        let split = MarkdownBlockSplitter.split("Один абзац")
        #expect(split.completed.isEmpty)
        #expect(split.tail == "Один абзац")
    }

    @Test("Finished paragraphs move to the completed blocks")
    func finishedParagraph() {
        let split = MarkdownBlockSplitter.split("Первый.\n\nВторой")
        #expect(split.completed == ["Первый."])
        #expect(split.tail == "Второй")
    }

    @Test("Several finished paragraphs are split apart")
    func severalParagraphs() {
        let split = MarkdownBlockSplitter.split("Первый.\n\nВторой.\n\nТретий")
        #expect(split.completed == ["Первый.", "Второй."])
        #expect(split.tail == "Третий")
    }

    @Test("A code fence is not split by empty lines inside it")
    func codeFenceIsOneBlock() {
        let text = """
        ```swift
        let a = 1

        let b = 2
        ```

        Хвост
        """
        let split = MarkdownBlockSplitter.split(text)
        #expect(split.completed.count == 1)
        #expect(split.completed[0].contains("let b = 2"))
        #expect(split.tail == "Хвост")
    }

    @Test("A table stays in one block")
    func tableIsOneBlock() {
        let text = """
        | a | b |
        | --- | --- |
        | 1 | 2 |

        Хвост
        """
        let split = MarkdownBlockSplitter.split(text)
        #expect(split.completed.count == 1)
        #expect(split.completed[0].contains("| 1 | 2 |"))
    }

    @Test("The stable hash does not change between calls")
    func stableHash() {
        let first = MarkdownBlockSplitter.stableHash("Привет")
        let second = MarkdownBlockSplitter.stableHash("Привет")
        #expect(first == second)
        #expect(first != MarkdownBlockSplitter.stableHash("Пока"))
    }
}
