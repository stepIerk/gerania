import Foundation
import GeraniaCore
import Testing

@Suite("Настройки микрофона")
@MainActor
struct VoiceInputSettingsTests {
    @Test("По умолчанию: всегда слушать, проверка голоса включена")
    func defaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "voice-input-\(UUID().uuidString)"))
        let settings = VoiceInputSettings(defaults: defaults)

        #expect(settings.listenMode == .always)
        #expect(settings.ownerGateEnabled)
        #expect(settings.keywordSensitivity == 0.6)
        #expect(settings.ownerThreshold == 0.5)
    }

    @Test("Выбор сохраняется между запусками")
    func persists() throws {
        let defaults = try #require(UserDefaults(suiteName: "voice-input-\(UUID().uuidString)"))
        let first = VoiceInputSettings(defaults: defaults)
        first.listenMode = .pushToTalk
        first.ownerGateEnabled = false
        first.ownerThreshold = 0.7

        let second = VoiceInputSettings(defaults: defaults)

        #expect(second.listenMode == .pushToTalk)
        #expect(!second.ownerGateEnabled)
        #expect(second.ownerThreshold == 0.7)
    }

    @Test("Режимы совпадают с командами «ушей»")
    func rawValues() {
        #expect(ListenMode.always.rawValue == "always")
        #expect(ListenMode.notWhileAnswering.rawValue == "not_while_answering")
        #expect(ListenMode.pushToTalk.rawValue == "push_to_talk")
        for mode in ListenMode.allCases {
            #expect(!mode.title.isEmpty && !mode.detail.isEmpty)
        }
    }
}
