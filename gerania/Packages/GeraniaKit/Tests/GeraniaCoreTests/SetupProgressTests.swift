import GeraniaCore
import Testing

@Suite("Мастер настройки: шаги")
struct SetupProgressTests {
    @Test("Начинается с Hermes и идёт по порядку")
    func order() {
        var progress = SetupProgress()
        #expect(progress.current == .hermes)

        progress.advance()
        #expect(progress.current == .model)
        progress.goBack()
        progress.goBack()
        #expect(progress.current == .hermes)
    }

    @Test("Пропуск отмечает шаг и переходит дальше")
    func skipMoves() {
        var progress = SetupProgress(current: .computer)

        progress.skip(.computer)

        #expect(progress.status(of: .computer) == .skipped)
        #expect(progress.current == .notifications)
        #expect(progress.status(of: .computer).isSettled)
    }

    @Test("Последний шаг не уходит дальше")
    func lastStep() {
        var progress = SetupProgress(current: .tryIt)

        progress.advance()

        #expect(progress.current == .tryIt)
        #expect(progress.isLastStep)
    }

    @Test("Красный обязательный шаг блокирует, необязательный — нет")
    func blockers() {
        var progress = SetupProgress()
        progress.set(.failed("нет"), for: .computer)
        #expect(progress.blockers.isEmpty)

        progress.set(.failed("нет hermes"), for: .hermes)
        progress.set(.ok("ок"), for: .notifications)

        #expect(progress.blockers == [.hermes])
        #expect(progress.readyCount == 1)
        #expect(!progress.status(of: .hermes).isSettled)
    }

    @Test("У каждого шага есть название и объяснение")
    func copy() {
        for step in SetupStep.allCases {
            #expect(!step.title.isEmpty)
            #expect(!step.explanation.isEmpty)
            #expect(!step.symbol.isEmpty)
        }
    }
}
