import Foundation
import GeraniaCore
import Testing

@Suite("Настройки микрофона")
@MainActor
struct VoiceInputSettingsTests {
    @Test("По умолчанию: всегда слушать, обычная защита от шума, Whisper")
    func defaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "voice-input-\(UUID().uuidString)"))
        let settings = VoiceInputSettings(defaults: defaults)

        #expect(settings.listenMode == .always)
        #expect(settings.noiseRejection == .normal)
        #expect(settings.wakePluginPath.isEmpty)
        #expect(settings.earsEnvironment.isEmpty)
    }

    @Test("Выбор сохраняется между запусками")
    func persists() throws {
        let defaults = try #require(UserDefaults(suiteName: "voice-input-\(UUID().uuidString)"))
        let first = VoiceInputSettings(defaults: defaults)
        first.listenMode = .pushToTalk
        first.noiseRejection = .strict
        first.wakePluginPath = "/tmp/my_wake.py"

        let second = VoiceInputSettings(defaults: defaults)

        #expect(second.listenMode == .pushToTalk)
        #expect(second.noiseRejection == .strict)
        #expect(second.earsEnvironment == ["GERA_WAKE_PLUGIN": "/tmp/my_wake.py"])
    }

    @Test("Строже защита — выше все пороги «ушей»")
    func noiseLevelsAreOrdered() {
        let keys = ["wake_min_prob", "speech_prob_silero", "speech_prob_spectral",
                    "partial_wake_speech_ratio", "min_speech_ratio"]
        for key in keys {
            let relaxed = NoiseRejection.relaxed.earsConfig[key] ?? -1
            let normal = NoiseRejection.normal.earsConfig[key] ?? -1
            let strict = NoiseRejection.strict.earsConfig[key] ?? -1
            #expect(relaxed < normal, "\(key)")
            #expect(normal < strict, "\(key)")
        }
    }

    @Test("Режимы совпадают с командами «ушей»")
    func rawValues() {
        #expect(ListenMode.always.rawValue == "always")
        #expect(ListenMode.notWhileAnswering.rawValue == "not_while_answering")
        #expect(ListenMode.pushToTalk.rawValue == "push_to_talk")
    }
}
