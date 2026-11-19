import Foundation
import GeraniaCore
@testable import GeraniaUI
import Testing

@Suite("Голосовой ввод: режимы и сочетания")
@MainActor
struct VoiceInputTests {
    @Test("Живой диалог «всегда слушать»: закрыт только чужим голосом")
    func alwaysMode() {
        #expect(open(.always))
        #expect(open(.always, modelSpeaking: true))
        #expect(!open(.always, otherSpeaking: true))
        #expect(open(.always, talkHeld: true, otherSpeaking: true))
    }

    @Test("«Не слушать во время ответа»: глух, пока Гера говорит, кроме ⌃⌥G")
    func notWhileAnswering() {
        #expect(open(.notWhileAnswering))
        #expect(!open(.notWhileAnswering, modelSpeaking: true))
        #expect(open(.notWhileAnswering, modelSpeaking: true, talkHeld: true))
    }

    @Test("Только по сочетанию: открыт, пока держим или после нажатия")
    func pushToTalk() {
        #expect(!open(.pushToTalk))
        #expect(open(.pushToTalk, talkHeld: true))
        #expect(open(.pushToTalk, talkLatched: true))
        #expect(!open(.pushToTalk, talkLatched: true, otherSpeaking: true))
    }

    @Test("Сочетание без включённого микрофона подсказывает, что делать")
    func talkWithoutMicrophone() {
        let defaults = UserDefaults(suiteName: "voice-input-ui-\(UUID().uuidString)") ?? .standard
        let model = AppModel(settings: GeraSettings(defaults: defaults))

        model.talkKeyDown()
        model.talkKeyUp()

        #expect(model.hud.hint?.contains("⌃⌥⌘G") == true)
    }

    @Test("Стоп в покое ничего не ломает")
    func stopWhenIdle() {
        let defaults = UserDefaults(suiteName: "voice-input-ui-\(UUID().uuidString)") ?? .standard
        let model = AppModel(settings: GeraSettings(defaults: defaults))

        model.stopAnswer()

        #expect(model.state == .idle)
    }

    private func open(
        _ mode: ListenMode,
        modelSpeaking: Bool = false,
        talkHeld: Bool = false,
        talkLatched: Bool = false,
        otherSpeaking: Bool = false
    ) -> Bool {
        LiveInputPolicy.isOpen(
            mode: mode,
            modelSpeaking: modelSpeaking,
            talkHeld: talkHeld,
            talkLatched: talkLatched,
            otherSpeaking: otherSpeaking
        )
    }
}
