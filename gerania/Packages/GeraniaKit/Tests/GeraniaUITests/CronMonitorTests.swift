import Foundation
import GeraniaCore
@testable import GeraniaUI
import HermesKit
import Testing

/// End to end on a temporary cron folder: Hermes writes a run document, the
/// monitor finds it once, survives a relaunch and feeds the HUD card.
@Suite("Наблюдатель планов")
@MainActor
struct CronMonitorTests {
    @Test("Новый результат приходит один раз и переживает перезапуск")
    func announcesOnce() throws {
        let cron = try makeCronDirectory()
        defer { try? FileManager.default.removeItem(at: cron) }
        let defaults = try makeDefaults()
        let monitor = CronMonitor(directory: cron, defaults: defaults)
        var delivered: [CronResult] = []
        monitor.onResults = { delivered += $0 }

        #expect(monitor.poll().isEmpty)
        #expect(monitor.scheduler == .notRunning)

        try writeRun(in: cron, job: "job-1", file: "2026-11-18_16-30-00.md", name: "Позвонить маме")
        try Data("\(Date().timeIntervalSince1970) 4113".utf8)
            .write(to: cron.appendingPathComponent("ticker_heartbeat"))

        let fresh = monitor.poll()
        #expect(fresh.count == 1)
        #expect(fresh.first?.title == "Позвонить маме")
        #expect(fresh.first?.digest.body == "Пора звонить.")
        #expect(delivered.map(\.id) == fresh.map(\.id))
        #expect(monitor.scheduler.isRunning)
        #expect(monitor.poll().isEmpty)

        let relaunched = CronMonitor(directory: cron, defaults: defaults)
        #expect(relaunched.poll().isEmpty)
    }

    @Test("Результат, записанный при выключенном приложении, приходит при запуске")
    func catchesUpAfterLaunch() throws {
        let cron = try makeCronDirectory()
        defer { try? FileManager.default.removeItem(at: cron) }
        let defaults = try makeDefaults()
        try writeRun(in: cron, job: "job-1", file: "old.md", name: "Старый", age: 3600)
        #expect(CronMonitor(directory: cron, defaults: defaults).poll().isEmpty)

        try writeRun(in: cron, job: "job-2", file: "night.md", name: "Ночной")

        let results = CronMonitor(directory: cron, defaults: defaults).poll()
        #expect(results.map(\.title) == ["Ночной"])
    }

    @Test("Карточка HUD: имя плана, ответ и счётчик остальных")
    func cardText() {
        let result = CronResult(
            output: CronOutput(jobID: "j", url: URL(fileURLWithPath: "/tmp/x.md"), modifiedAt: Date()),
            digest: CronOutputDigest(title: "Брифинг", body: "Сегодня три встречи.", isFailure: false)
        )

        let text = AppModel.cronCardText(result, others: 2)

        #expect(text.hasPrefix("**⏰ Брифинг**"))
        #expect(text.contains("Сегодня три встречи."))
        #expect(text.contains("Ещё результатов: 2"))
    }

    @Test("Карточка показывается, когда Гера свободна")
    func cardShownWhenIdle() throws {
        let defaults = try makeDefaults()
        let settings = GeraSettings(defaults: defaults)
        settings.notifications = false
        let model = AppModel(settings: settings)
        let result = CronResult(
            output: CronOutput(jobID: "j", url: URL(fileURLWithPath: "/tmp/x.md"), modifiedAt: Date()),
            digest: CronOutputDigest(title: "Напоминание", body: "Пора.", isFailure: false)
        )

        model.announceCronResults([result])

        #expect(model.state == .done)
        #expect(model.hud.streamedText.contains("Напоминание"))
    }

    // MARK: - Helpers

    /// `age` is seconds in the past; the default puts the file a second ahead,
    /// so it is newer than the baseline whatever the file-system resolution.
    private func writeRun(
        in cron: URL,
        job: String,
        file: String,
        name: String,
        age: TimeInterval = -1
    ) throws {
        let folder = cron.appendingPathComponent("output/\(job)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(file)
        let text = "# Cron Job: \(name)\n\n**Job ID:** \(job)\n\n## Response\n\nПора звонить.\n"
        try Data(text.utf8).write(to: url)
        let date = Date().addingTimeInterval(-age)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func makeCronDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gerania-test-cron-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "GeraniaUITests-cron-\(UUID().uuidString)"))
    }
}
