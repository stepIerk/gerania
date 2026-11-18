import Foundation
import GeraniaCore
import Testing

@Suite("Файл памяти")
struct MemoryDocumentTests {
    private let url = URL(fileURLWithPath: "/tmp/USER.md")

    private func document(entries: [String], limit: Int? = nil) -> MemoryDocument {
        MemoryDocument(
            kind: .user,
            url: url,
            limit: limit,
            entries: entries,
            fingerprint: .missing
        )
    }

    @Test("Формат Hermes: записи разделены строкой с §")
    func parseDelimiter() {
        let raw = "Первая запись\n§\nВторая\n\n§\n\nТретья"

        let parsed = MemoryDocument.parse(
            kind: .user,
            url: url,
            raw: raw,
            fingerprint: .missing
        )

        #expect(parsed.entries == ["Первая запись", "Вторая", "Третья"])
        #expect(parsed.characters == "Первая запись\n§\nВторая\n§\nТретья".unicodeScalars.count)
        #expect(!parsed.isOverLimit)
    }

    @Test("Пустой файл — пустой список")
    func parseEmpty() {
        let parsed = MemoryDocument.parse(
            kind: .notes,
            url: url,
            raw: "",
            fingerprint: .missing
        )

        #expect(parsed.entries.isEmpty)
        #expect(parsed.isEmpty)
        #expect(parsed.countText == "0 записей")
        #expect(parsed.serialized.isEmpty)
    }

    @Test("CRLF из чужого редактора читается так же")
    func parseCRLF() {
        let parsed = MemoryDocument.parse(
            kind: .user,
            url: url,
            raw: "Первая\r\n§\r\nВторая\r\n",
            fingerprint: .missing
        )

        #expect(parsed.entries == ["Первая", "Вторая"])
    }

    @Test("Добавление обрезает пробелы и считает символы")
    func adding() throws {
        let updated = try document(entries: ["Старая"]).adding("  Новая запись \n")

        #expect(updated.entries == ["Старая", "Новая запись"])
        #expect(updated.characters == "Старая\n§\nНовая запись".unicodeScalars.count)
    }

    @Test("Пустая запись не сохраняется")
    func emptyEntry() {
        #expect(throws: MemoryFileError.emptyEntry) {
            try document(entries: []).adding("   \n  ")
        }
    }

    @Test("Строка с § не ломает формат")
    func delimiterEntry() {
        #expect(throws: MemoryFileError.delimiterInEntry) {
            try document(entries: []).adding("Первая\n§\nВторая")
        }
    }

    @Test("Лимит проверяется до записи")
    func limit() {
        let current = document(entries: ["12345"], limit: 15)

        #expect(throws: MemoryFileError.overLimit(kind: .user, limit: 15, characters: 18)) {
            try current.adding("1234567890")
        }
        #expect(current.entries == ["12345"])
    }

    @Test("Замена и удаление адресуются по индексу")
    func replaceAndRemove() throws {
        let current = document(entries: ["Первая", "Вторая", "Третья"])

        let replaced = try current.replacing(at: 1, with: "Новая вторая")
        let removed = try replaced.removing(at: 0)

        #expect(replaced.entries == ["Первая", "Новая вторая", "Третья"])
        #expect(removed.entries == ["Новая вторая", "Третья"])
        #expect(throws: MemoryFileError.missingEntry) {
            try current.removing(at: 9)
        }
    }

    @Test("Очистка оставляет пустой файл")
    func cleared() {
        let current = document(entries: ["Первая", "Вторая"])

        let cleared = current.cleared()

        #expect(cleared.entries.isEmpty)
        #expect(cleared.serialized.isEmpty)
        #expect(cleared.fingerprint == current.fingerprint)
    }

    @Test("Файл больше лимита виден, но новые записи не влезают")
    func overLimitFile() {
        let long = String(repeating: "я", count: 30)
        let current = document(entries: [long], limit: 20)

        #expect(current.isOverLimit)
        #expect(current.remaining == 0)
        #expect(throws: MemoryFileError.overLimit(kind: .user, limit: 20, characters: 36)) {
            try current.adding("ещё")
        }
    }
}
