import HermesKit
import Testing

@Suite("HermesKit")
struct HermesEventTests {
    @Test("Errors carry Russian descriptions")
    func errorDescriptions() {
        let error = HermesError.binaryNotFound

        #expect(error.errorDescription?.contains("hermes") == true)
    }

    @Test("Session summaries are identified by id")
    func sessionIdentity() {
        let summary = SessionSummary(id: "local-1", title: "Тест", messageCount: 2)

        #expect(summary.id == "local-1")
        #expect(summary.messageCount == 2)
    }
}
