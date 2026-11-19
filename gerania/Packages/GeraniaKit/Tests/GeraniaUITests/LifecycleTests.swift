import Foundation
import GeraniaCore
@testable import GeraniaUI
import RealtimeKit
import Testing

@Suite("Жизненный цикл и лимиты Live")
@MainActor
struct LifecycleTests {
    private func model() -> AppModel {
        let defaults = UserDefaults(suiteName: "GeraniaUITests-life-\(UUID().uuidString)") ?? .standard
        return AppModel(settings: GeraSettings(defaults: defaults))
    }

    @Test("Без работы ⌘Q не спрашивает")
    func idleQuit() {
        #expect(model().busyReasonForQuit == nil)
    }

    @Test("Во время ответа ⌘Q просит подтверждения")
    func busyQuit() {
        let model = model()
        model.apply(state: .streaming)

        #expect(model.busyReasonForQuit == "Гера отвечает на запрос.")
    }

    @Test("Лимит выбранной модели — Live берёт запасную")
    func liveFallsBack() throws {
        let model = model()
        model.settings.liveModel = "gemini-3.8-live"
        model.liveQuota.markExhausted("gemini-3.8-live")

        #expect(try model.availableLiveModel() == "gemini-3.8-live-extended-thinking")
    }

    @Test("Все модели на паузе — обычный режим и время возврата")
    func allPaused() {
        let model = model()
        for entry in LiveModelCatalog.entries {
            model.liveQuota.markExhausted(entry.id)
        }

        #expect(throws: LiveError.quotaExceeded) {
            try model.availableLiveModel()
        }
        #expect(model.liveFailureHint(LiveError.quotaExceeded).hasPrefix("Лимит Gemini Live исчерпан — до "))
        #expect(AppModel.quotaHint(until: nil) == "Лимит Gemini Live исчерпан — отвечаю в обычном режиме")
    }
}
