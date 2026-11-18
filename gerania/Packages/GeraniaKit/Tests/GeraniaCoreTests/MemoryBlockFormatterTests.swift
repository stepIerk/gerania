import Foundation
import GeraniaCore
import Testing

@Suite("Блок памяти для системного промпта")
struct MemoryBlockFormatterTests {
    private func document(_ kind: MemoryKind, _ entries: [String], limit: Int) -> MemoryDocument {
        MemoryDocument.parse(
            kind: kind,
            url: URL(fileURLWithPath: "/tmp/\(kind.fileName)"),
            raw: entries.joined(separator: MemoryKind.delimiter),
            limit: limit,
            fingerprint: .missing
        )
    }

    @Test("Счётчик символов группируется через запятую")
    func grouping() {
        #expect(MemoryBlockFormatter.grouped(0) == "0")
        #expect(MemoryBlockFormatter.grouped(999) == "999")
        #expect(MemoryBlockFormatter.grouped(1000) == "1,000")
        #expect(MemoryBlockFormatter.grouped(1375) == "1,375")
        #expect(MemoryBlockFormatter.grouped(2200) == "2,200")
    }

    @Test("Строка использования считает процент и бюджет")
    func usage() {
        let doc = document(.notes, ["abc"], limit: 100)
        #expect(MemoryBlockFormatter.usage(for: doc) == "3% — 3/100 chars")
    }

    @Test("Блок содержит заголовок, разделитель и записи")
    func block() {
        let doc = document(.notes, ["abc", "de"], limit: 100)
        let expected = [
            MemoryBlockFormatter.separator,
            "MEMORY (your personal notes) [8% — 8/100 chars]",
            MemoryBlockFormatter.separator,
            "abc",
            "§",
            "de",
        ].joined(separator: "\n")
        #expect(MemoryBlockFormatter.block(for: doc) == expected)
    }

    @Test("Пустой файл не даёт блока, но предпросмотр показывает бюджет")
    func empty() {
        let doc = document(.notes, [], limit: 2200)
        #expect(MemoryBlockFormatter.block(for: doc).isEmpty)
        let preview = MemoryBlockFormatter.preview(for: doc)
        #expect(preview.contains("MEMORY (your personal notes) [0% — 0/2,200 chars]"))
        #expect(preview.contains("— пусто"))
    }

    @Test("Предпросмотр непустого файла содержит записи")
    func previewContent() {
        let doc = document(.notes, ["Любит Swift."], limit: 2200)
        let preview = MemoryBlockFormatter.preview(for: doc)
        #expect(preview.contains("Любит Swift."))
        #expect(preview.contains("MEMORY (your personal notes)"))
    }
}
