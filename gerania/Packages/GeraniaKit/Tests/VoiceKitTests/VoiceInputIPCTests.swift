import Foundation
import Testing
import VoiceKit

@Suite("IPC микрофона")
struct VoiceInputIPCTests {
    @Test("Режим слушания и flush кодируются в NDJSON")
    func commands() throws {
        let mode = try object(VoiceCommand.listenMode("push_to_talk").payload)
        #expect(mode == ["type": "listen_mode", "mode": "push_to_talk"])
        #expect(try object(VoiceCommand.flush.payload) == ["type": "flush"])
    }

    @Test("«Уши» сообщают детекторы")
    func engines() {
        let line = #"{"type":"engines","wake":"Whisper","keyword":false,"speech":"silero","#
            + #""speech_detail":"Silero VAD"}"#
        #expect(VoiceEvent.decode(line) == .engines(
            wake: "Whisper",
            keyword: false,
            speech: "silero",
            speechDetail: "Silero VAD"
        ))
    }

    private func object(_ payload: String) throws -> [String: String] {
        let value = try JSONSerialization.jsonObject(with: Data(payload.utf8))
        return (value as? [String: String]) ?? [:]
    }
}
