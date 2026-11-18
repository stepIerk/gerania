import Foundation
import GeraniaCore
import Testing

@Suite("Черновик профиля")
struct MemoryProfileDraftTests {
    @Test("Полная анкета даёт шесть записей")
    func fullAnswers() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Moscow"))
        let draft = MemoryProfileDraft(
            name: "Степан",
            city: "Москва",
            study: "МГУ, 3 курс",
            stack: "Swift, Python",
            style: "Коротко, с примерами кода",
            notes: "Люблю тёмную тему"
        )

        let entries = draft.entries(timeZone: zone)

        #expect(entries == [
            "Обращаться: Степан.",
            "Город: Москва. Часовой пояс: Europe/Moscow.",
            "Учёба и работа: МГУ, 3 курс.",
            "Стек: Swift, Python.",
            "Стиль ответов: Коротко, с примерами кода.",
            "Ещё: Люблю тёмную тему.",
        ])
    }

    @Test("Пустые ответы пропускаются")
    func emptyAnswers() {
        let draft = MemoryProfileDraft(name: "  Степан  ")

        let entries = draft.entries()

        #expect(entries == ["Обращаться: Степан."])
    }

    @Test("Город добавляет часовой пояс Мака")
    func cityAddsTimeZone() {
        let draft = MemoryProfileDraft(city: "Москва")

        let entries = draft.entries()

        #expect(entries.count == 1)
        #expect(entries.first?.hasPrefix("Город: Москва. Часовой пояс: ") == true)
    }

    @Test("Точка в конце не удваивается")
    func punctuation() {
        let draft = MemoryProfileDraft(style: "Коротко.")

        #expect(draft.entries() == ["Стиль ответов: Коротко."])
    }

    @Test("Пустая анкета ничего не пишет")
    func emptyDraft() {
        #expect(MemoryProfileDraft().entries().isEmpty)
    }
}
