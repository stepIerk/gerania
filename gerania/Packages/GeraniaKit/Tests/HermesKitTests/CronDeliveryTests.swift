import Foundation
import GeraniaCore
@testable import HermesKit
import Testing

@Suite("Доставка планов")
struct CronDeliveryTests {
    // MARK: - Scheduler heartbeat

    @Test("Свежий heartbeat — планировщик работает")
    func freshHeartbeat() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        let status = CronSchedulerStatus.evaluate(heartbeat: "999970.5 4113", now: now)

        #expect(status.isRunning)
        #expect(status == .running(age: 29.5))
    }

    @Test("Старый heartbeat — планировщик остановлен")
    func staleHeartbeat() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        let status = CronSchedulerStatus.evaluate(heartbeat: "990000 4113\n", now: now)

        #expect(!status.isRunning)
        #expect(status == .stalled(age: 10000))
        #expect(status.detail.contains("ч назад"))
    }

    @Test("Нет файла или мусор — планировщик не запускался")
    func missingHeartbeat() throws {
        let now = Date()
        #expect(CronSchedulerStatus.evaluate(heartbeat: nil, now: now) == .notRunning)
        #expect(CronSchedulerStatus.evaluate(heartbeat: "", now: now) == .notRunning)
        #expect(CronSchedulerStatus.evaluate(heartbeat: "abc 1", now: now) == .notRunning)

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(CronSchedulerStatus.read(cronDirectory: directory) == .notRunning)

        let stamp = "\(now.timeIntervalSince1970 - 5) 42"
        try Data(stamp.utf8).write(to: directory.appendingPathComponent("ticker_heartbeat"))
        #expect(CronSchedulerStatus.read(cronDirectory: directory, now: now).isRunning)
    }

    // MARK: - Run document

    @Test("Из файла результата берутся имя и ответ")
    func digestOfRun() {
        let markdown = """
        # Cron Job: Позвонить маме

        **Job ID:** abc123
        **Run Time:** 2026-11-18T16:30:00+03:00

        ## Prompt

        Напомни позвонить маме. Формат: ## Response в конце.

        ## Response

        Пора позвонить маме: она ждёт звонка до шести.
        """

        let digest = CronOutputDigest.parse(markdown)

        #expect(digest.title == "Позвонить маме")
        #expect(digest.body == "Пора позвонить маме: она ждёт звонка до шести.")
        #expect(!digest.isFailure)
    }

    @Test("Упавший запуск помечается ошибкой")
    func digestOfFailure() {
        let markdown = "# Cron Job: job-1 (FAILED)\n\nprovider timeout\n"

        let digest = CronOutputDigest.parse(markdown)

        #expect(digest.title == "job-1")
        #expect(digest.isFailure)
        #expect(digest.body == "provider timeout")
    }

    @Test("Длинный ответ обрезается")
    func digestClips() {
        let markdown = "## Response\n\n" + String(repeating: "а", count: 1000)

        let digest = CronOutputDigest.parse(markdown, limit: 100)

        #expect(digest.title == nil)
        #expect(digest.body.count == 101)
        #expect(digest.body.hasSuffix("…"))
    }

    // MARK: - Dedup

    @Test("Первый просмотр — только точка отсчёта, без уведомлений")
    func trackerBaseline() {
        var tracker = CronResultTracker()
        let old = output("job", "old.md", at: 100)

        #expect(tracker.takeNew(from: [old]).isEmpty)
        #expect(tracker.watermark == Date(timeIntervalSince1970: 100))
        #expect(tracker.takeNew(from: [old]).isEmpty)
    }

    @Test("Новый результат объявляется ровно один раз")
    func trackerAnnouncesOnce() {
        var tracker = CronResultTracker()
        let old = output("job", "old.md", at: 100)
        _ = tracker.takeNew(from: [old])
        let first = output("job", "a.md", at: 200)
        let twin = output("other", "b.md", at: 200)

        let fresh = tracker.takeNew(from: [twin, first, old])

        #expect(Set(fresh.map(\.id)) == [first.id, twin.id])
        #expect(tracker.takeNew(from: [twin, first, old]).isEmpty)
        let late = output("other", "c.md", at: 200)
        #expect(tracker.takeNew(from: [late, twin, first, old]).map(\.id) == [late.id])
    }

    @Test("Пропущенные при выключенном приложении приходят после запуска")
    func trackerCatchUp() {
        var running = CronResultTracker()
        _ = running.takeNew(from: [output("job", "old.md", at: 100)])
        var relaunched = CronResultTracker(watermark: running.watermark, seenIDs: running.seenIDs)
        let missed = [output("job", "morning.md", at: 400), output("job", "night.md", at: 300)]

        let fresh = relaunched.takeNew(from: missed)

        #expect(fresh.map(\.fileName) == ["night.md", "morning.md"])
    }

    @Test("Пустая папка задаёт точку отсчёта «сейчас»")
    func trackerEmptyBaseline() {
        var tracker = CronResultTracker()
        let now = Date(timeIntervalSince1970: 500)

        #expect(tracker.takeNew(from: [], now: now).isEmpty)
        #expect(tracker.watermark == now)
        #expect(tracker.takeNew(from: [output("job", "x.md", at: 400)]).isEmpty)
        #expect(tracker.takeNew(from: [output("job", "y.md", at: 600)]).count == 1)
    }

    // MARK: - Job fields and errors

    @Test("last_fire_error и просрочка видны в задаче")
    func heldJob() throws {
        let raw = try JSONValue(from: Data("""
        {"id": "j1", "name": "Тест", "state": "scheduled", "enabled": true,
         "next_run_at": "2026-11-18T13:00:00+00:00",
         "last_fire_error": {"at": "2026-11-18T13:01:00+00:00", "detail": "the gateway is not running"}}
        """.utf8))
        let job = try #require(CronJob.parse(raw))
        let due = try #require(job.nextRunDate)

        #expect(job.lastFireError == "the gateway is not running")
        #expect(job.isOverdue(now: due.addingTimeInterval(600)))
        #expect(!job.isOverdue(now: due.addingTimeInterval(60)))
    }

    @Test("Запуск планировщика вызывает gateway ensure")
    func ensureGatewayArguments() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calls = CallLog()
        let store = CronJobsStore(directory: directory, runner: { arguments in
            await calls.append(arguments)
            return CronCommandResult(exitCode: 0)
        })

        try await store.ensureGateway(timeout: 15)

        #expect(await calls.items == [["gateway", "ensure", "--json", "--timeout", "15"]])
    }

    @Test("Ошибки объясняются по-русски")
    func russianErrors() {
        #expect(CronError.binaryNotFound.errorDescription?.hasPrefix("Hermes недоступен") == true)
        let failed = CronError.commandFailed(exitCode: 2, message: "no such job")
        #expect(failed.errorDescription == "Hermes не выполнил команду: no such job")
        #expect(CronError.invalidRequest("Заполните").errorDescription == "Заполните")
    }

    // MARK: - Helpers

    private func output(_ job: String, _ name: String, at seconds: TimeInterval) -> CronOutput {
        CronOutput(
            jobID: job,
            url: URL(fileURLWithPath: "/tmp/cron/output/\(job)/\(name)"),
            modifiedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gerania-cron-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor CallLog {
    private(set) var items: [[String]] = []

    func append(_ arguments: [String]) {
        items.append(arguments)
    }
}
