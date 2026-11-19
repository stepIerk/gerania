import Foundation
import GeraniaCore
import HermesKit
import OSLog
import RealtimeKit
import VoiceKit

/// Gathers the facts and the recent log for `DiagnosticsReport`.
///
/// Only reads: settings, file presence, TCC states, the heartbeat of the
/// scheduler and the app's own log (`OSLogStore` of this process, no
/// entitlement needed). Values marked `.private` in the log stay `<private>`.
enum DiagnosticsCollector {
    static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "com.yourname.Gerania"
    }

    static var hermesLogsDirectory: URL {
        CronJobsStore.defaultDirectory().deletingLastPathComponent().appendingPathComponent("logs")
    }

    @MainActor
    static func build(settings: GeraSettings, logWindow: TimeInterval = 3600) async -> DiagnosticsReport {
        var sections = facts(settings: settings)
        let notifications = await CronNotifier.access()
        sections.append(DiagnosticsReport.Section(title: "Уведомления", rows: [("Доступ", notifications.text)]))
        let since = Date().addingTimeInterval(-logWindow)
        let id = subsystem
        let lines = await Task.detached(priority: .utility) {
            DiagnosticsCollector.recentLogLines(since: since, subsystem: id)
        }.value
        return DiagnosticsReport(sections: sections, logLines: lines)
    }

    @MainActor
    static func facts(settings: GeraSettings) -> [DiagnosticsReport.Section] {
        let info = Bundle.main.infoDictionary ?? [:]
        let config = OnboardingModel.config(settings)
        let hermesPath = (try? config.hermesBinary().path) ?? "не найден"
        let scheduler = CronSchedulerStatus.read(cronDirectory: CronJobsStore.defaultDirectory())
        let model = settings.provider.isEmpty ? "по умолчанию Hermes" : "\(settings.provider)/\(settings.model)"
        return [
            DiagnosticsReport.Section(title: "Приложение", rows: [
                ("Версия", info["CFBundleShortVersionString"] as? String ?? "?"),
                ("Сборка", info["CFBundleVersion"] as? String ?? "?"),
                ("Bundle ID", subsystem),
                ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
                ("GeraniaKit", HermesKitInfo.version),
            ]),
            DiagnosticsReport.Section(title: "Hermes", rows: [
                ("Бинарь", hermesPath),
                ("Транспорт", String(describing: settings.transport)),
                ("Модель", model),
                ("Планировщик", "\(scheduler.title). \(scheduler.detail)"),
                ("Логи Hermes", hermesLogsDirectory.path),
            ]),
            DiagnosticsReport.Section(title: "Голос", rows: [
                ("Голос включён", settings.voiceEnabled ? "да" : "нет"),
                ("Микрофон", MicrophoneAccess.statusName),
                ("Живой диалог", settings.liveVoiceEnabled ? "включён" : "выключен"),
                ("Модель Live", settings.liveModel),
                ("Ключ Gemini", LiveCredentials.isConfigured ? "есть в Связке ключей" : "нет"),
            ]),
            DiagnosticsReport.Section(title: "Сеть", rows: [
                ("Интернет", NetworkStatus.shared.isOnline ? "есть" : "нет"),
            ]),
        ]
    }

    static func recentLogLines(since date: Date, subsystem: String) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: date)
            let predicate = NSPredicate(format: "subsystem == %@", subsystem)
            let formatter = ISO8601DateFormatter()
            var lines: [String] = []
            for case let entry as OSLogEntryLog in try store.getEntries(at: position, matching: predicate) {
                lines.append("\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)")
            }
            return lines
        } catch {
            return ["Журнал недоступен: \(error.localizedDescription)"]
        }
    }
}
