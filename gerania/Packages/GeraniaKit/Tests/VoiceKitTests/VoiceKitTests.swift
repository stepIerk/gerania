import Foundation
import Testing
import VoiceKit

@Suite("VoiceKit")
struct VoiceKitTests {
    @Test("Placeholder version is exposed")
    func version() {
        #expect(VoiceKitInfo.version == "0.1.0")
    }

    @Test("Suspend and resume are NDJSON commands")
    func suspendAndResume() {
        #expect(VoiceCommand.suspend.payload == "{\"type\":\"suspend\"}")
        #expect(VoiceCommand.resume.payload == "{\"type\":\"resume\"}")
    }

    @Test("Mute keeps the phrase by default")
    func muteKeepsThePhrase() throws {
        let payload = try decode(VoiceCommand.mute(seconds: 0.2))

        #expect(payload["type"] as? String == "mute")
        #expect(payload["sec"] as? Double == 0.2)
        #expect(payload["keep_phrase"] as? Bool == true)
    }

    @Test("Mute can reset the phrase explicitly")
    func hardMute() throws {
        let payload = try decode(VoiceCommand.mute(seconds: 0.45, keepPhrase: false))

        #expect(payload["keep_phrase"] as? Bool == false)
    }

    private func decode(_ command: VoiceCommand) throws -> [String: Any] {
        let data = try #require(command.payload.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
