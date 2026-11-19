import Foundation
import Testing
@testable import VoiceKit

@Suite("Wake-слово и голос владельца")
struct WakeEngineTests {
    @Test("Новые команды «ушам» кодируются в NDJSON")
    func commands() throws {
        let mode = try object(VoiceCommand.listenMode("push_to_talk").payload)
        #expect(mode == ["type": "listen_mode", "mode": "push_to_talk"])
        #expect(try object(VoiceCommand.flush.payload) == ["type": "flush"])
        let payload = Data(VoiceCommand.ownerGate(enabled: true).payload.utf8)
        let gate = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(gate["type"] as? String == "owner_gate")
        #expect(gate["enabled"] as? Bool == true)
    }

    @Test("События детекторов разбираются")
    func events() {
        let engines = #"{"type":"engines","keyword":true,"keyword_detail":"Porcupine","#
            + #""owner":false,"owner_detail":"голос владельца не записан"}"#
        #expect(VoiceEvent.decode(engines) == .engines(
            keyword: true,
            keywordDetail: "Porcupine",
            owner: false,
            ownerDetail: "голос владельца не записан"
        ))
        #expect(VoiceEvent.decode(#"{"type":"wake_rejected","score":0.12}"#) == .wakeRejected(score: 0.12))
        #expect(VoiceEvent.decode(#"{"type":"speaker","who":"other","score":0.1}"#) == .speaker(.other))
        #expect(VoiceEvent.decode(#"{"type":"speaker","who":"alien"}"#) == nil)
        #expect(VoiceEvent.decode(#"{"type":"enroll_progress","percent":42.5}"#) == .enrollProgress(percent: 42.5))
        #expect(VoiceEvent.decode(#"{"type":"enroll_done","path":"/tmp/p"}"#) == .enrollDone(path: "/tmp/p"))
    }

    @Test("Чего не хватает для детектора «Гера»")
    func status() {
        let empty = WakeEngine.Status(hasKey: false, hasKeyword: false, hasModel: false, hasOwnerProfile: false)
        #expect(!empty.keywordReady)
        #expect(empty.missing.count == 3)

        let ready = WakeEngine.Status(hasKey: true, hasKeyword: true, hasModel: true, hasOwnerProfile: false)
        #expect(ready.keywordReady)
        #expect(ready.missing.isEmpty)
    }

    @Test("Окружение «ушей» содержит только существующие файлы")
    func environment() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("gerania-wake-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let source = home.appendingPathComponent("picked.ppn")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: source)
        try WakeEngine.install(source, as: WakeEngine.keywordURL(homeDirectory: home.path))

        let environment = WakeEngine.environment(sensitivity: 0.6, ownerThreshold: 0.55, homeDirectory: home.path)

        #expect(environment["GERA_WAKE_KEYWORD"] == WakeEngine.keywordURL(homeDirectory: home.path).path)
        #expect(environment["GERA_WAKE_MODEL"] == nil)
        #expect(environment["GERA_OWNER_PROFILE"] == nil)
        #expect(environment["GERA_WAKE_SENSITIVITY"] == "0.60")
        #expect(environment["GERA_OWNER_THRESHOLD"] == "0.55")
    }

    @Test("Поток NDJSON режется на строки, хвост ждёт продолжения")
    func lineReader() {
        let reader = LineReader()

        #expect(reader.append(Data("{\"a\":1}\n{\"b\"".utf8)) == ["{\"a\":1}"])
        #expect(reader.append(Data(":2}\n".utf8)) == ["{\"b\":2}"])
    }

    private func object(_ payload: String) throws -> [String: String] {
        let value = try JSONSerialization.jsonObject(with: Data(payload.utf8))
        return (value as? [String: String]) ?? [:]
    }
}
