import Foundation
import GeraniaCore
@testable import HermesKit
import Testing

@Suite("Планы Hermes")
struct CronJobsStoreTests {
    // MARK: - Reading

    @Test("Пустой каталог — пустой список")
    func missingFileIsEmpty() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CronJobsStore(directory: directory, runner: { _ in CronCommandResult(exitCode: 0) })

        #expect(try await store.load().isEmpty)
    }

    @Test("Читает задачи и разбирает расписания")
    func loadFixture() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try fixtureData.write(to: directory.appendingPathComponent("jobs.json"))
        let store = CronJobsStore(directory: directory, runner: { _ in CronCommandResult(exitCode: 0) })

        let jobs = try await store.load()

        #expect(jobs.count == 3)
        let brief = try #require(jobs.first { $0.id == "job-brief" })
        #expect(brief.name == "Утренний брифинг")
        #expect(brief.scheduleKind == "cron")
        #expect(brief.scheduleText == "ежедневно в 08:00")
        #expect(brief.nextRunDate != nil)
        #expect(brief.lastStatus == "success")
        #expect(brief.timezone == "Europe/Moscow")
        #expect(brief.repeatTimes == 10)

        let reminder = try #require(jobs.first { $0.id == "job-reminder" })
        #expect(reminder.scheduleKind == "once")
        #expect(reminder.scheduleText.hasPrefix("один раз"))

        let interval = try #require(jobs.first { $0.id == "job-interval" })
        #expect(interval.scheduleText == "каждые 2 ч")
        #expect(interval.isPaused)
        #expect(interval.stateText == "на паузе")
    }

    @Test("Повреждённый файл даёт понятную ошибку")
    func corruptFixture() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("jobs.json"))
        let store = CronJobsStore(directory: directory, runner: { _ in CronCommandResult(exitCode: 0) })

        await #expect(throws: CronError.self) {
            _ = try await store.load()
        }
    }

    @Test("Шестизначные микросекунды разбираются")
    func microseconds() {
        let date = CronJob.date("2026-11-18T08:00:00.123456+00:00")

        #expect(date != nil)
        #expect(CronJob.date("2026-11-18T08:00:00+00:00") != nil)
        #expect(CronJob.date("") == nil)
        #expect(CronJob.date(nil) == nil)
    }

    // MARK: - Actions

    @Test("Действия вызывают hermes с нужными аргументами")
    func actionArguments() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = RunnerRecorder()
        let store = CronJobsStore(directory: directory, runner: { arguments in
            await recorder.record(arguments)
            return CronCommandResult(exitCode: 0)
        })

        try await store.pause("abc")
        try await store.resume("abc")
        try await store.resume("abc", runNow: true)
        try await store.runNow("abc")
        try await store.remove("abc")

        #expect(await recorder.calls == [
            ["cron", "pause", "abc"],
            ["cron", "resume", "abc"],
            ["cron", "resume", "--run-now", "abc"],
            ["cron", "run", "abc"],
            ["cron", "remove", "abc"],
        ])
    }

    @Test("Создание собирает аргументы create")
    func createArguments() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = RunnerRecorder()
        let store = CronJobsStore(directory: directory, runner: { arguments in
            await recorder.record(arguments)
            return CronCommandResult(exitCode: 0)
        })

        try await store.create(CronJobRequest(
            name: "Брифинг",
            schedule: "0 8 * * *",
            prompt: "Собери брифинг",
            timezone: "Europe/Moscow"
        ))

        #expect(await recorder.calls == [[
            "cron", "create", "0 8 * * *", "Собери брифинг",
            "--name", "Брифинг", "--deliver", "local", "--timezone", "Europe/Moscow",
        ]])
    }

    @Test("Пустой запрос не доходит до hermes")
    func invalidRequest() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = RunnerRecorder()
        let store = CronJobsStore(directory: directory, runner: { arguments in
            await recorder.record(arguments)
            return CronCommandResult(exitCode: 0)
        })

        await #expect(throws: CronError.self) {
            try await store.create(CronJobRequest(name: "", schedule: " ", prompt: " "))
        }
        #expect(await recorder.calls.isEmpty)
    }

    @Test("Ошибка CLI приходит с текстом Hermes")
    func commandFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CronJobsStore(directory: directory, runner: { _ in
            CronCommandResult(exitCode: 2, stderr: "no such job\n")
        })

        do {
            try await store.pause("missing")
            Issue.record("Ожидалась ошибка")
        } catch let error as CronError {
            #expect(error == .commandFailed(exitCode: 2, message: "no such job"))
        }
    }

    // MARK: - Output

    @Test("Результаты сортируются от новых к старым")
    func outputsSorted() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jobDirectory = root.appendingPathComponent("output/job-brief", isDirectory: true)
        try FileManager.default.createDirectory(at: jobDirectory, withIntermediateDirectories: true)
        let old = jobDirectory.appendingPathComponent("old.md")
        let new = jobDirectory.appendingPathComponent("new.md")
        try Data("старый".utf8).write(to: old)
        try Data("новый".utf8).write(to: new)
        let past = Date(timeIntervalSince1970: 1000)
        let future = Date(timeIntervalSince1970: 2000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: new.path)

        let outputs = CronOutputStore.recent(in: root)

        #expect(outputs.map(\.fileName) == ["new.md", "old.md"])
        #expect(outputs.first?.jobID == "job-brief")
        let newest = try #require(outputs.first)
        #expect(try CronOutputStore.read(newest) == "новый")
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gerania-cron-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var fixtureData: Data {
        Data("""
        {
          "jobs": [
            {
              "id": "job-brief",
              "name": "Утренний брифинг",
              "prompt": "Собери брифинг",
              "schedule": {"kind": "cron", "expr": "0 8 * * *", "display": "ежедневно в 08:00"},
              "schedule_display": "ежедневно в 08:00",
              "state": "scheduled",
              "enabled": true,
              "next_run_at": "2026-11-18T08:00:00.123456+00:00",
              "last_run_at": "2026-11-17T08:00:00+00:00",
              "last_status": "success",
              "deliver": "local",
              "timezone": "Europe/Moscow",
              "repeat": {"times": 10, "completed": 1}
            },
            {
              "id": "job-reminder",
              "name": "Напоминание",
              "prompt": "Позвонить",
              "schedule": {"kind": "once", "run_at": "2026-11-18T12:00:00+00:00"},
              "state": "scheduled",
              "enabled": true
            },
            {
              "id": "job-interval",
              "name": "Проверка",
              "prompt": "Проверь",
              "schedule": {"kind": "interval", "minutes": 120},
              "state": "paused",
              "enabled": false
            }
          ]
        }
        """.utf8)
    }
}

private actor RunnerRecorder {
    private(set) var calls: [[String]] = []

    func record(_ arguments: [String]) {
        calls.append(arguments)
    }
}
