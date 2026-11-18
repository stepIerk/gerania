import Foundation
import GeraniaCore
@testable import GeraniaUI
import Testing

@Suite("AppModel: поток ответа")
@MainActor
struct AppModelStreamTests {
    private func model() -> AppModel {
        let defaults = UserDefaults(suiteName: "GeraniaUITests-\(UUID().uuidString)") ?? .standard
        return AppModel(settings: GeraSettings(defaults: defaults))
    }

    @Test("Новый запрос переводит модель в thinking")
    func turnStarted() {
        let model = model()

        model.dispatch(.turnStarted)

        #expect(model.state == .thinking(tools: []))
    }

    @Test("Фикстура проигрывается как поток дельт")
    func fixtureStreams() async {
        let model = model()
        model.dispatch(.turnStarted)

        await model.streamFixture("Привет, мир", named: "test")

        #expect(model.hud.streamedText == "Привет, мир")
        #expect(model.state == .done)
    }

    @Test("Длинный ответ увеличивает время автоскрытия")
    func longAnswerDelaysHide() {
        let model = model()
        model.hud.appendDelta(String(repeating: "a", count: 1000))

        let delay = model.adjustedHideDelay(6)

        #expect(delay == 11)
        #expect(model.adjustedHideDelay(6) <= 30)
    }

    @Test("Обычный ответ не меняет время автоскрытия")
    func shortAnswerKeepsDelay() {
        let model = model()

        #expect(model.adjustedHideDelay(6) == 6)
        #expect(model.adjustedHideDelay(0) == 0)
    }
}
