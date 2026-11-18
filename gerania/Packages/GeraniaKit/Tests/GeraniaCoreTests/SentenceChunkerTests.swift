import Foundation
import GeraniaCore
import Testing

@Suite("SentenceChunker")
struct SentenceChunkerTests {
    private func chunks(_ text: String) -> [String] {
        var chunker = SentenceChunker()
        var result = chunker.feed(text)
        if let last = chunker.flush() {
            result.append(last)
        }
        return result
    }

    @Test("Одно предложение даёт один кусок")
    func singleSentence() {
        let result = chunks("Это достаточно длинное предложение для озвучки.\n")

        #expect(result == ["Это достаточно длинное предложение для озвучки."])
    }

    @Test("Два предложения дают два куска")
    func twoSentences() {
        let result = chunks(
            "Первое предложение достаточно длинное для озвучки.\n"
                + "Второе предложение тоже достаточно длинное.\n"
        )

        #expect(result.count == 2)
        #expect(result[0].hasPrefix("Первое"))
        #expect(result[1].hasPrefix("Второе"))
    }

    @Test("Короткий фрагмент ждёт следующего текста")
    func shortFragmentWaits() {
        var chunker = SentenceChunker()
        let result = chunker.feed("Коротко.\n")

        #expect(result.isEmpty)
        #expect(!chunker.pendingText.isEmpty)
    }

    @Test("Восклицательный знак заканчивает фразу")
    func exclamationBoundary() {
        let result = chunks("Отличная новость прямо сейчас!\n")

        #expect(result == ["Отличная новость прямо сейчас!"])
    }

    @Test("Вопросительный знак заканчивает фразу")
    func questionBoundary() {
        let result = chunks("Что там с погодой сегодня?\n")

        #expect(result == ["Что там с погодой сегодня?"])
    }

    @Test("Многоточие заканчивает фразу")
    func ellipsisBoundary() {
        let result = chunks("Ну и всё, значит, пора прощаться...\n")

        #expect(result.count == 1)
        #expect(result[0].hasSuffix("..."))
    }

    @Test("Перенос строки заканчивает фразу")
    func newlineBoundary() {
        let result = chunks("Строка без знака конца, но достаточно длинная\nвторая строка\n")

        #expect(result.count >= 1)
        #expect(result[0].contains("Строка без знака конца"))
    }

    @Test("Сокращение «т.е.» не режет предложение")
    func abbreviationIsNotABoundary() {
        let result = chunks("То есть это просто пример длинного предложения.\n")

        #expect(result.count == 1)
        #expect(result[0].contains("То есть"))
    }

    @Test("Дробь не режет предложение")
    func decimalIsNotABoundary() {
        let result = chunks("Значение числа 3.14 вот такое получается на самом деле.\n")

        #expect(result.count == 1)
        #expect(result[0].contains("3.14"))
    }

    @Test("Блок кода не читается")
    func codeFenceIsSkipped() {
        let text = """
        Текст перед блоком кода достаточно длинный.
        ```swift
        let value = 3.14
        print("что-то очень длинное внутри кода")
        ```
        Текст после блока кода тоже достаточно длинный.
        """
        let result = chunks(text)

        #expect(result.contains { $0.contains("Текст перед блоком кода") })
        #expect(!result.contains { $0.contains("let value") })
        #expect(result.contains { $0.contains("Текст после блока кода") })
    }

    @Test("Таблица не читается")
    func tableIsSkipped() {
        let text = """
        Строка перед таблицей достаточно длинная для озвучки.
        | Ключ | Значение |
        | --- | --- |
        | один | два |
        Строка после таблицы тоже достаточно длинная.
        """
        let result = chunks(text)

        #expect(result.contains { $0.contains("Строка перед таблицей") })
        #expect(!result.contains { $0.contains("Значение") })
        #expect(result.contains { $0.contains("Строка после таблицы") })
    }

    @Test("Markdown очищается перед озвучкой")
    func markdownIsCleaned() {
        let result = chunks("**Жирный** и `код` в одном предложении подряд.\n")

        #expect(result.count == 1)
        #expect(!result[0].contains("*"))
        #expect(!result[0].contains("`"))
    }

    @Test("Остаток отдаётся при flush")
    func flushReturnsTheRest() {
        var chunker = SentenceChunker()
        _ = chunker.feed("Короткий остаток без конца")
        let last = chunker.flush()

        #expect(last == "Короткий остаток без конца")
    }

    @Test("Сброс очищает буфер")
    func resetClearsBuffer() {
        var chunker = SentenceChunker()
        _ = chunker.feed("Что-то накопленное")
        chunker.reset()

        #expect(chunker.pendingText.isEmpty)
        #expect(chunker.flush() == nil)
    }

    @Test("Поток дельт собирает предложение")
    func streamBuildsSentence() {
        var chunker = SentenceChunker()
        var result: [String] = []
        for delta in ["Это ", "очень ", "длинное ", "предложение ", "для ", "озвучки."] {
            result += chunker.feed(delta)
        }

        #expect(result.isEmpty)
        if let last = chunker.flush() {
            result.append(last)
        }
        #expect(result == ["Это очень длинное предложение для озвучки."])
    }

    @Test("Пустой текст не даёт кусков")
    func emptyText() {
        #expect(chunks("").isEmpty)
        #expect(chunks("\n\n").isEmpty)
    }

    @Test("Граница по точке с заглавной новой фразы")
    func boundaryAfterDot() {
        let result = chunks(
            "Первая часть предложения достаточно длинная. Вторая часть тоже длинная.\n"
        )

        #expect(result.count == 2)
    }
}
