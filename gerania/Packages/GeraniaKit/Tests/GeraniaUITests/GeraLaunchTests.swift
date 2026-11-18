import Foundation
import GeraniaCore
@testable import GeraniaUI
import Testing

@Suite("Запуск Геры")
@MainActor
struct GeraLaunchTests {
    private func model() -> AppModel {
        let defaults = UserDefaults(suiteName: "GeraniaUITests-\(UUID().uuidString)") ?? .standard
        return AppModel(settings: GeraSettings(defaults: defaults))
    }

    @Test("Запуск включает голос и поднимает уши")
    func startEnablesVoice() async {
        let model = model()
        model.microphoneRequest = { true }

        await model.startGera()

        #expect(model.settings.voiceEnabled)
        #expect(model.isVoiceRunning)
    }

    @Test("Без доступа к микрофону уши не поднимаются")
    func startWithoutMicrophone() async {
        let model = model()
        model.microphoneRequest = { false }

        await model.startGera()

        #expect(model.settings.voiceEnabled)
        #expect(!model.isVoiceRunning)
        #expect(model.launchError != nil)
    }

    @Test("Остановка выключает голос")
    func stopDisablesVoice() async {
        let model = model()
        model.microphoneRequest = { true }
        await model.startGera()

        await model.stopGera()

        #expect(!model.settings.voiceEnabled)
        #expect(!model.isVoiceRunning)
    }

    @Test("Маршрут gerania://start запускает Герю")
    func urlStartsGera() async throws {
        let model = model()
        model.microphoneRequest = { true }
        let url = try #require(URL(string: "gerania://start"))

        model.handle(url: url)
        // The route works in a task: wait for it to finish.
        for _ in 0 ..< 50 where !model.isVoiceRunning {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(model.isVoiceRunning)
    }

    @Test("Обычный запуск приложения — не автозапуск при входе")
    func launchIsNotLoginItem() {
        #expect(LaunchOrigin.isLoginItem == false)
    }
}
