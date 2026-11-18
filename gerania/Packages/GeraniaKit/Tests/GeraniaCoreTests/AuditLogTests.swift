import Foundation
import GeraniaCore
import Testing

@Suite("Журнал действий")
struct AuditLogTests {
    private func temporaryLog() -> (AuditLog, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gerania-audit-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("audit.jsonl")
        return (AuditLog(url: url), directory)
    }

    @Test("Записи читаются в порядке добавления")
    func roundTrip() async {
        let (log, directory) = temporaryLog()
        defer { try? FileManager.default.removeItem(at: directory) }

        await log.append(AuditEntry(tool: "web_search", detail: "swift", ok: true, summary: "2 результата"))
        await log.append(AuditEntry(tool: "terminal", detail: "ls", ok: false, summary: "код 1"))

        let entries = await log.recent(limit: 10)

        #expect(entries.count == 2)
        #expect(entries[0].tool == "web_search")
        #expect(entries[0].ok == true)
        #expect(entries[0].summary == "2 результата")
        #expect(entries[1].tool == "terminal")
        #expect(entries[1].ok == false)
    }

    @Test("Лимит оставляет только новые записи")
    func limit() async {
        let (log, directory) = temporaryLog()
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0 ..< 5 {
            await log.append(AuditEntry(tool: "tool-\(index)", ok: true))
        }

        let entries = await log.recent(limit: 2)

        #expect(entries.map(\.tool) == ["tool-3", "tool-4"])
    }

    @Test("Битые строки не ломают чтение")
    func brokenLine() async throws {
        let (log, directory) = temporaryLog()
        defer { try? FileManager.default.removeItem(at: directory) }
        await log.append(AuditEntry(tool: "web_search", ok: true))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let handle = try FileHandle(forWritingTo: log.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{ not json\n".utf8))
        try handle.close()

        let entries = await log.recent(limit: 10)

        #expect(entries.count == 1)
        #expect(entries.first?.tool == "web_search")
    }

    @Test("Секреты в аргументах скрываются")
    func redaction() {
        let bearer = AuditLog.redacted("curl -H 'Authorization: Bearer abc123'")
        let key = AuditLog.redacted("API_KEY=super-secret")
        let password = AuditLog.redacted("password: hunter2")

        #expect(bearer?.contains("abc123") == false)
        #expect(bearer?.contains("Bearer ***") == true)
        #expect(key?.contains("super-secret") == false)
        #expect(password?.contains("hunter2") == false)
    }

    @Test("Длинный аргумент обрезается")
    func truncation() {
        let long = String(repeating: "a", count: 500)

        let redacted = AuditLog.redacted(long)

        #expect(redacted?.count == 300)
        #expect(redacted?.hasSuffix("…") == true)
    }

    @Test("Путь по умолчанию лежит в Application Support")
    func defaultPath() {
        #expect(AuditLog.defaultURL().path.hasSuffix("/Gerania/audit.jsonl"))
    }
}
