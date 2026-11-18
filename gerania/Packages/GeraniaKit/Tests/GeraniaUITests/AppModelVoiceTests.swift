import Foundation
import GeraniaCore
@testable import GeraniaUI
import Testing
import VoiceKit

@Suite("Голос в AppModel")
@MainActor
struct AppModelVoiceTests {
    private func model() -> AppModel {
        let defaults = UserDefaults(suiteName: "GeraniaUITests-\(UUID().uuidString)") ?? .standard
        return AppModel(settings: GeraSettings(defaults: defaults))
    }

    @Test("Wake без команды включает listening")
    func wakeStartsListening() {
        let model = model()

        model.handleVoice(.wake(inlineCommand: nil))

        guard case .listening = model.state else {
            Issue.record("expected the listening state")
            return
        }
    }

    @Test("Команда уходит в запрос и попадает в HUD")
    func commandStartsRequest() {
        let model = model()

        model.handleVoice(.command(text: "погода в Москве", via: .inline))

        #expect(model.hud.heardText == "погода в Москве")
        #expect(model.currentMode == .voice)
        #expect(model.state == .thinking(tools: []))
    }

    @Test("Новое Гера во время стрима прерывает запрос")
    func bargeInDuringStreaming() {
        let model = model()
        model.dispatch(.turnStarted)
        model.dispatch(.textDelta("Ответ"))

        model.handleVoice(.wake(inlineCommand: nil))

        #expect(model.hud.hint == "Прервано новым запросом")
        guard case .listening = model.state else {
            Issue.record("expected the listening state after the barge-in")
            return
        }
    }

    @Test("Стоп-слово во время работы останавливает всё")
    func stopDuringWork() {
        let model = model()
        model.dispatch(.turnStarted)
        model.dispatch(.textDelta("Ответ"))

        model.handleVoice(.stop(scope: .busy))

        #expect(model.hud.hint == "Остановлено")
        #expect(model.state == .idle)
    }

    @Test("Отмена ввода показывает подсказку и гасит HUD")
    func cancelInput() {
        let model = model()

        model.handleVoice(.stop(scope: .input))

        #expect(model.hud.hint == "Ввод отменён")
        #expect(model.state == .idle)
    }

    @Test("Таймаут ожидания команды")
    func awaitTimeout() {
        let model = model()

        model.handleVoice(.awaitTimeout)

        #expect(model.hud.hint == "Команда не прозвучала")
    }

    @Test("Уровень микрофона сглаживается и попадает в HUD")
    func levelUpdatesHud() {
        let model = model()

        model.handleVoice(.level(rms: 0.02, threshold: 0.01, active: true))

        // Сглаживание: attack 0.6 — первый кадр не даёт полной амплитуды.
        #expect(model.hud.micLevel > 0.5)
        #expect(model.hud.micLevel < 1.0)

        for _ in 0 ..< 10 {
            model.handleVoice(.level(rms: 0.02, threshold: 0.01, active: true))
        }
        #expect(model.hud.micLevel > 0.95)
    }

    @Test("Тихий микрофон обнуляет уровень")
    func quietLevel() {
        let model = model()
        model.handleVoice(.level(rms: 0.2, threshold: 0.01, active: true))

        model.handleVoice(.level(rms: 0.0001, threshold: 0.01, active: false))

        #expect(model.hud.micLevel == 0)
    }
}
