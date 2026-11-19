import Foundation
import GeraniaCore
@testable import GeraniaUI
import Testing
import VoiceKit

@Suite("Голосовой ввод: режимы и сочетания")
@MainActor
struct VoiceInputTests {
    @Test("Живой диалог «всегда слушать»: микрофон открыт")
    func alwaysMode() {
        #expect(open(.always))
        #expect(open(.always, modelSpeaking: true))
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
    }

    @Test("«Уши» сообщают, чем ловят «Гера» и отличают речь")
    func engines() {
        let defaults = UserDefaults(suiteName: "voice-input-ui-\(UUID().uuidString)") ?? .standard
        let model = AppModel(settings: GeraSettings(defaults: defaults))

        let event = VoiceEvent.engines(wake: "Whisper", keyword: false, speech: "silero", speechDetail: "Silero VAD")
        model.handleVoiceInputEvent(event)

        #expect(model.voiceInput.usesNeuralVAD)
        #expect(model.voiceInput.wakeDetail == "Whisper")
        #expect(!model.voiceInput.keywordActive)
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
        talkLatched: Bool = false
    ) -> Bool {
        LiveInputPolicy.isOpen(
            mode: mode,
            modelSpeaking: modelSpeaking,
            talkHeld: talkHeld,
            talkLatched: talkLatched
        )
    }
}
