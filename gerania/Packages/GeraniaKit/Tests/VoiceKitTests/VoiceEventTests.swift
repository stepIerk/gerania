import Foundation
import Testing
import VoiceKit

@Suite("VoiceEvent")
struct VoiceEventTests {
    @Test("Готово")
    func ready() {
        #expect(
            VoiceEvent.decode("{\"type\":\"ready\",\"model\":\"whisper\"}") == .ready(model: "whisper")
        )
    }

    @Test("Уровень микрофона")
    func level() {
        let event = VoiceEvent.decode("{\"type\":\"level\",\"rms\":0.02,\"thr\":0.01,\"active\":true}")

        #expect(event == .level(rms: 0.02, threshold: 0.01, active: true))
    }

    @Test("Начало и конец фразы")
    func utterance() {
        #expect(VoiceEvent.decode("{\"type\":\"utterance_start\"}") == .utteranceStart)
        #expect(VoiceEvent.decode("{\"type\":\"utterance_end\",\"dur\":1.5}") == .utteranceEnd(duration: 1.5))
    }

    @Test("Отсев")
    func filtered() {
        #expect(VoiceEvent.decode("{\"type\":\"filtered\",\"reason\":\"хлопок\"}") == .filtered(reason: "хлопок"))
    }

    @Test("Распознанный текст")
    func transcript() {
        let event = VoiceEvent.decode("{\"type\":\"transcript\",\"text\":\"Гера\",\"no_speech\":0.1,\"logprob\":-0.4}")

        #expect(event == .transcript(text: "Гера", noSpeech: 0.1, logprob: -0.4))
    }

    @Test("Wake с командой и без")
    func wake() {
        #expect(VoiceEvent.decode("{\"type\":\"wake\"}") == .wake(inlineCommand: nil))
        #expect(
            VoiceEvent.decode("{\"type\":\"wake\",\"inline_command\":\"погода\"}")
                == .wake(inlineCommand: "погода")
        )
    }

    @Test("Частичный текст")
    func partial() {
        #expect(
            VoiceEvent.decode("{\"type\":\"partial\",\"text\":\"какая погода\"}")
                == .partial(text: "какая погода")
        )
    }

    @Test("Команда")
    func command() {
        #expect(
            VoiceEvent.decode("{\"type\":\"command\",\"text\":\"погода\",\"via\":\"inline\"}")
                == .command(text: "погода", via: .inline)
        )
        #expect(
            VoiceEvent.decode("{\"type\":\"command\",\"text\":\"погода\",\"via\":\"followup\"}")
                == .command(text: "погода", via: .followup)
        )
        #expect(
            VoiceEvent.decode("{\"type\":\"command\",\"text\":\"погода\",\"via\":\"partial\"}")
                == .command(text: "погода", via: .partial)
        )
        #expect(
            VoiceEvent.decode("{\"type\":\"command\",\"text\":\"погода\",\"via\":\"final\"}")
                == .command(text: "погода", via: .final)
        )
    }

    @Test("Остановка")
    func stop() {
        #expect(VoiceEvent.decode("{\"type\":\"stop\",\"scope\":\"input\"}") == .stop(scope: .input))
        #expect(VoiceEvent.decode("{\"type\":\"stop\",\"scope\":\"busy\"}") == .stop(scope: .busy))
        #expect(VoiceEvent.decode("{\"type\":\"stop\",\"scope\":\"explicit\"}") == .stop(scope: .explicit))
    }

    @Test("Таймаут ожидания и ошибка")
    func timeoutAndError() {
        #expect(VoiceEvent.decode("{\"type\":\"await_timeout\"}") == .awaitTimeout)
        #expect(VoiceEvent.decode("{\"type\":\"error\",\"message\":\"бум\"}") == .error(message: "бум"))
        #expect(VoiceEvent.decode("{\"type\":\"bye\"}") == .bye)
    }

    @Test("Пауза и возврат микрофона")
    func suspendedAndResumed() {
        #expect(VoiceEvent.decode("{\"type\":\"suspended\"}") == .suspended)
        #expect(VoiceEvent.decode("{\"type\":\"resumed\"}") == .resumed)
    }

    @Test("Мусор не роняет поток")
    func garbageIsIgnored() {
        #expect(VoiceEvent.decode("") == nil)
        #expect(VoiceEvent.decode("не json") == nil)
        #expect(VoiceEvent.decode("{\"type\":\"неизвестно\"}") == nil)
        #expect(VoiceEvent.decode("[1,2,3]") == nil)
    }
}
