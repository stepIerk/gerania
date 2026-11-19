import Foundation
import GeraniaCore
import Testing

@Suite("Отчёт диагностики")
struct DiagnosticsReportTests {
    @Test("Ключи провайдеров и токены скрываются")
    func redactsSecrets() {
        let text = """
        GEMINI_API_KEY=AIzaSyA1234567890abcdefghijklmnop
        openai sk-proj-abcdefghijklmnopqrstuvwx
        Authorization: Bearer abcdef.ghijkl.mnopqr
        wss://localhost:8642/ws?ticket=SECRET123&x=1
        token: ghp_abcdefghijklmnopqrstuvwxyz012345
        """

        let redacted = SecretRedactor.redact(text)

        #expect(!redacted.contains("AIzaSy"))
        #expect(!redacted.contains("sk-proj"))
        #expect(!redacted.contains("ghijkl"))
        #expect(!redacted.contains("SECRET123"))
        #expect(!redacted.contains("ghp_"))
        #expect(redacted.contains("GEMINI_API_KEY="))
        #expect(redacted.contains("?ticket=\(SecretRedactor.mask)&x=1"))
    }

    @Test("Обычный текст не трогается")
    func keepsPlainText() {
        let text = "Планировщик Hermes работает. Модель: gemini/gemini-2.5-flash"

        #expect(SecretRedactor.redact(text) == text)
    }

    @Test("Отчёт содержит разделы и журнал, без секретов")
    func reportText() {
        let report = DiagnosticsReport(
            createdAt: Date(timeIntervalSince1970: 0),
            sections: [DiagnosticsReport.Section(title: "Hermes", rows: [("Бинарь", "/usr/local/bin/hermes")])],
            logLines: ["live: ready", "key=AIzaSyA1234567890abcdefghijklmnop"]
        )

        let text = report.text

        #expect(text.contains("## Hermes"))
        #expect(text.contains("Бинарь: /usr/local/bin/hermes"))
        #expect(text.contains("live: ready"))
        #expect(!text.contains("AIzaSy"))
        #expect(report.fileName.hasPrefix("Gerania-diagnostics-"))
        #expect(report.fileName.hasSuffix(".txt"))
    }

    @Test("Журнал обрезается до последних строк")
    func trimsLog() {
        let lines = (0 ..< DiagnosticsReport.maxLogLines + 10).map { "line \($0)" }

        let report = DiagnosticsReport(sections: [], logLines: lines)

        #expect(report.logLines.count == DiagnosticsReport.maxLogLines)
        #expect(report.logLines.last == lines.last)
    }
}
