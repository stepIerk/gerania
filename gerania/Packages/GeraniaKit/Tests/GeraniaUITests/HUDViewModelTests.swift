import Foundation
import GeraniaCore
import GeraniaUI
import Testing

@Suite("Модель HUD")
@MainActor
struct HUDViewModelTests {
    @Test("Дельты собираются в блоки markdown")
    func deltasBecomeBlocks() {
        let model = HUDViewModel()

        model.appendDelta("Первый абзац.\n\n")
        model.appendDelta("Второй абзац.\n\n")
        model.appendDelta("Хвост")
        model.flushStream()

        #expect(model.blocks.count == 2)
        #expect(model.blocks.first == "Первый абзац.")
        #expect(model.tail == "Хвост")
    }

    @Test("Незакрытый блок кода закрывается санитайзером")
    func openFenceIsClosed() {
        let model = HUDViewModel()

        model.appendDelta("```swift\nlet a = 1")
        model.flushStream()

        #expect(model.tail.contains("```"))
        #expect(model.tail.contains("let a = 1"))
    }

    @Test("Инструменты запоминаются и закрываются")
    func toolsLifecycle() {
        let model = HUDViewModel()

        model.startTool(ToolChip(id: "1", name: "terminal", detail: "ls"))
        #expect(model.tools.count == 1)
        #expect(model.tools[0].isFinished == false)

        model.finishTool(id: "1", ok: true)
        #expect(model.tools[0].isFinished)
    }

    @Test("Вывод инструмента не теряется при завершении")
    func toolOutputSurvivesFinish() {
        let model = HUDViewModel()

        model.startTool(ToolChip(id: "1", name: "browser_exec", detail: "screenshot"))
        model.attachOutput(id: "1", imagePath: "/tmp/shot.png", summary: "Страница YouTube")
        model.finishTool(id: "1", ok: true)

        #expect(model.tools[0].imagePath == "/tmp/shot.png")
        #expect(model.tools[0].summary == "Страница YouTube")
        #expect(model.tools[0].isFinished)
    }

    @Test("Сброс очищает ответ")
    func resetClearsAnswer() {
        let model = HUDViewModel()
        model.appendDelta("Текст")
        model.appendReasoning("Мысль")

        model.reset()

        #expect(model.streamedText.isEmpty)
        #expect(model.reasoningText.isEmpty)
        #expect(model.blocks.isEmpty)
    }
}
