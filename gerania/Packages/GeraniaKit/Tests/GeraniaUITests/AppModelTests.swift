import Foundation
import GeraniaCore
@testable import GeraniaUI
import Testing

@Suite("AppModel")
@MainActor
struct AppModelTests {
    private func model() -> AppModel {
        let defaults = UserDefaults(suiteName: "GeraniaUITests-\(UUID().uuidString)") ?? .standard
        return AppModel(settings: GeraSettings(defaults: defaults))
    }

    @Test("Starts idle with the waveform menu-bar icon")
    func initialState() {
        let model = model()

        #expect(model.state == .idle)
        #expect(model.menuBarSymbol == "waveform")
    }

    @Test("Listens on the gerania://listen route")
    func listenRoute() throws {
        let model = model()
        let url = try #require(URL(string: "gerania://listen"))

        model.handle(url: url)

        guard case .listening = model.state else {
            Issue.record("expected listening")
            return
        }
    }

    @Test("Debug state route sets a fake state")
    func debugStateRoute() throws {
        let model = model()
        let url = try #require(URL(string: "gerania://debug/state?name=streaming"))

        model.handle(url: url)

        #expect(model.state == .streaming)
    }

    @Test("Driving the computer changes the menu-bar icon")
    func computerUseIndicator() {
        let model = model()
        model.hud.startTool(ToolChip(id: "c1", name: "computer_use", detail: "capture · Safari"))

        #expect(model.hud.isComputerUseActive)
        #expect(model.menuBarSymbol == "display")
        #expect(model.menuBarLabel.contains("компьютер"))

        model.hud.finishTool(id: "c1", ok: true)

        #expect(!model.hud.isComputerUseActive)
        #expect(model.menuBarSymbol == "waveform")
    }

    @Test("Reminder comes after ten minutes of control")
    func computerUseReminder() async throws {
        let model = model()
        model.hud.startTool(ToolChip(id: "c1", name: "computer_use"))

        model.startComputerUseWatch(delay: 0.01)
        var attempts = 0
        while model.hud.computerUseNotice == nil, attempts < 40 {
            try await Task.sleep(for: .milliseconds(25))
            attempts += 1
        }

        #expect(model.hud.computerUseNotice != nil)
        #expect(model.hud.computerUseNotice?.contains("10 минут") == true)
    }

    @Test("Finishing the tool cancels the reminder")
    func computerUseReminderCancelled() async throws {
        let model = model()
        model.hud.startTool(ToolChip(id: "c1", name: "computer_use"))

        model.startComputerUseWatch(delay: 0.01)
        model.stopComputerUseWatch()
        try await Task.sleep(for: .milliseconds(100))

        #expect(model.hud.computerUseNotice == nil)
    }

    @Test("Инструменты попадают в журнал")
    func toolIsRecorded() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gerania-model-audit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = AuditLog(url: directory.appendingPathComponent("audit.jsonl"))
        let defaults = UserDefaults(suiteName: "GeraniaUITests-\(UUID().uuidString)") ?? .standard
        let model = AppModel(settings: GeraSettings(defaults: defaults), auditLog: log)

        model.handle(.toolStarted(id: "t1", name: "web_search", detail: "swift 6"))
        model.handle(.toolOutput(id: "t1", imagePath: nil, summary: "2 результата"))
        model.handle(.toolFinished(id: "t1", ok: true))

        var entries: [AuditEntry] = []
        var attempts = 0
        while entries.isEmpty, attempts < 40 {
            entries = await log.recent(limit: 10)
            try await Task.sleep(for: .milliseconds(25))
            attempts += 1
        }

        #expect(entries.first?.tool == "web_search")
        #expect(entries.first?.detail == "swift 6")
        #expect(entries.first?.summary == "2 результата")
        #expect(entries.first?.ok == true)
    }
}
