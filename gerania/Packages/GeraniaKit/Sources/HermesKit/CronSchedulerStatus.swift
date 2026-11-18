import Foundation

/// Whether the Hermes cron ticker is alive, read from `<cron>/ticker_heartbeat`.
///
/// The ticker lives inside the Hermes gateway and rewrites the file once per
/// loop (every 60 s) as `<epoch> <pid>`. `hermes cron status` treats a stamp
/// older than three intervals plus 20 s as stale; Gerania uses the same bound,
/// so the tab and the CLI agree. Reading a file keeps the check cheap enough to
/// poll and does not start any process.
public enum CronSchedulerStatus: Sendable, Equatable {
    /// The ticker stamped the file recently.
    case running(age: TimeInterval)
    /// A stamp exists but is old: the gateway stopped or hangs.
    case stalled(age: TimeInterval)
    /// No stamp at all: the gateway never ran for this Hermes home.
    case notRunning

    /// `TICKER_INTERVAL_SECONDS * 3 + 20` in Hermes.
    public static let freshness: TimeInterval = 200

    public static func read(cronDirectory: URL, now: Date = Date()) -> CronSchedulerStatus {
        let url = cronDirectory.appendingPathComponent("ticker_heartbeat")
        let text = try? String(contentsOf: url, encoding: .utf8)
        return evaluate(heartbeat: text, now: now)
    }

    /// Pure part of `read`, for the tests.
    public static func evaluate(heartbeat: String?, now: Date) -> CronSchedulerStatus {
        guard let heartbeat,
              let first = heartbeat.split(whereSeparator: \.isWhitespace).first,
              let epoch = Double(first)
        else {
            return .notRunning
        }
        let age = max(0, now.timeIntervalSince1970 - epoch)
        return age <= freshness ? .running(age: age) : .stalled(age: age)
    }

    public var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    /// Short label for the status row.
    public var title: String {
        switch self {
        case .running: "Планировщик Hermes работает"
        case .stalled: "Планировщик Hermes остановлен"
        case .notRunning: "Планировщик Hermes не запущен"
        }
    }

    /// What the person should know or do.
    public var detail: String {
        switch self {
        case let .running(age):
            "Последний тик \(Int(age)) с назад. Напоминания сработают вовремя."
        case let .stalled(age):
            "Последний тик \(Self.minutes(age)) назад. Пока gateway не работает, планы не срабатывают. "
                + "Нажмите «Запустить планировщик» или откройте чат с Герой."
        case .notRunning:
            "Gateway Hermes ещё не запускался, поэтому планы не сработают. "
                + "Нажмите «Запустить планировщик» или откройте чат с Герой."
        }
    }

    private static func minutes(_ age: TimeInterval) -> String {
        let minutes = Int(age / 60)
        if minutes < 60 {
            return "\(max(1, minutes)) мин"
        }
        return "\(minutes / 60) ч"
    }
}
