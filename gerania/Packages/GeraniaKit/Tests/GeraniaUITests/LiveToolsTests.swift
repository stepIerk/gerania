@testable import GeraniaUI
import RealtimeKit
import Testing

@Suite("Live tools")
struct LiveToolsTests {
    @Test("The model can end the dialog")
    func finishConversation() {
        let tool = LiveTools.all.first { $0.name == "finish_conversation" }

        #expect(tool != nil)
        #expect(tool?.behavior == .nonBlocking)
        #expect(tool?.parameters == .object([
            "type": .string("object"),
            "properties": .object([:]),
            "required": .array([]),
        ]))
    }

    @Test("Every declared tool is unique")
    func uniqueNames() {
        let names = LiveTools.all.map(\.name)
        #expect(Set(names).count == names.count)
    }
}
