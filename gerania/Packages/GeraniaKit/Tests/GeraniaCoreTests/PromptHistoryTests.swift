import Foundation
import GeraniaCore
import Testing

@Suite("PromptHistory")
struct PromptHistoryTests {
    @Test("Промпты добавляются в начало списка")
    func addsNewestFirst() {
        var history = PromptHistory()

        history.add("первый")
        history.add("второй")

        #expect(history.prompts == ["второй", "первый"])
    }

    @Test("Пустые промпты и повтор последнего игнорируются")
    func ignoresEmptyAndDuplicate() {
        var history = PromptHistory()

        history.add("   ")
        history.add("вопрос")
        history.add("вопрос")

        #expect(history.prompts == ["вопрос"])
    }

    @Test("Хранится не больше пятидесяти промптов")
    func keepsFifty() {
        var history = PromptHistory()

        for index in 0 ..< 60 {
            history.add("вопрос \(index)")
        }

        #expect(history.prompts.count == 50)
        #expect(history.prompts.first == "вопрос 59")
        #expect(history.prompts.last == "вопрос 10")
    }

    @Test("Назад по истории идут от новых к старым")
    func goesBack() {
        var history = PromptHistory()
        history.add("старый")
        history.add("новый")

        let first = history.prompt(before: nil)
        #expect(first?.prompt == "новый")
        #expect(first?.cursor == 0)

        let second = history.prompt(before: first?.cursor)
        #expect(second?.prompt == "старый")
        #expect(second?.cursor == 1)

        #expect(history.prompt(before: second?.cursor) == nil)
    }

    @Test("Вперёд по истории возвращаются новые промпты")
    func goesForward() {
        var history = PromptHistory()
        history.add("старый")
        history.add("новый")

        let back = history.prompt(before: nil)
        let older = history.prompt(before: back?.cursor)
        let forward = history.prompt(after: older?.cursor)

        #expect(forward?.prompt == "новый")
        #expect(history.prompt(after: 0) == nil)
    }

    @Test("Очистка убирает все промпты")
    func clears() {
        var history = PromptHistory()
        history.add("вопрос")

        history.clear()

        #expect(history.prompts.isEmpty)
    }
}
