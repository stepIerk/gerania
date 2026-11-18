import Foundation
import GeraniaCore

/// One scheduled job from `~/.hermes/cron/jobs.json`.
///
/// The record is read-only here: Hermes owns the file. The settings tab shows
/// the human fields and calls `hermes cron pause|resume|run|remove` for actions,
/// so the on-disk format never has to be written by Gerania.
public struct CronJob: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let prompt: String
    public let scheduleDisplay: String
    public let scheduleKind: String?
    public let scheduleMinutes: Int?
    public let scheduleExpression: String?
    public let runAt: String?
    public let state: String
    public let isEnabled: Bool
    public let nextRunAt: String?
    public let lastRunAt: String?
    public let lastStatus: String?
    public let lastError: String?
    public let deliver: String?
    public let timezone: String?
    public let repeatTimes: Int?
    public let repeatCompleted: Int?

    public init(
        id: String,
        name: String,
        prompt: String = "",
        scheduleDisplay: String = "",
        scheduleKind: String? = nil,
        scheduleMinutes: Int? = nil,
        scheduleExpression: String? = nil,
        runAt: String? = nil,
        state: String = "scheduled",
        isEnabled: Bool = true,
        nextRunAt: String? = nil,
        lastRunAt: String? = nil,
        lastStatus: String? = nil,
        lastError: String? = nil,
        deliver: String? = nil,
        timezone: String? = nil,
        repeatTimes: Int? = nil,
        repeatCompleted: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.scheduleDisplay = scheduleDisplay
        self.scheduleKind = scheduleKind
        self.scheduleMinutes = scheduleMinutes
        self.scheduleExpression = scheduleExpression
        self.runAt = runAt
        self.state = state
        self.isEnabled = isEnabled
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.lastStatus = lastStatus
        self.lastError = lastError
        self.deliver = deliver
        self.timezone = timezone
        self.repeatTimes = repeatTimes
        self.repeatCompleted = repeatCompleted
    }

    public var isPaused: Bool {
        !isEnabled || state == "paused"
    }

    public var isCompleted: Bool {
        state == "completed"
    }

    /// Russian label for the row badge.
    public var stateText: String {
        if isPaused {
            return "на паузе"
        }
        switch state {
        case "completed": return "завершён"
        case "error": return "ошибка"
        default: return "по расписанию"
        }
    }

    /// Human schedule: interval minutes, one-shot date or the Hermes display.
    public var scheduleText: String {
        switch scheduleKind {
        case "interval":
            if let minutes = scheduleMinutes {
                if minutes >= 60, minutes % 60 == 0 {
                    let hours = minutes / 60
                    return hours == 1 ? "каждый час" : "каждые \(hours) ч"
                }
                return "каждые \(minutes) мин"
            }
        case "once":
            if let date = Self.date(runAt) {
                return "один раз \(date.formatted(date: .abbreviated, time: .shortened))"
            }
        default:
            break
        }
        return scheduleDisplay.isEmpty ? (scheduleExpression ?? "—") : scheduleDisplay
    }

    public var nextRunDate: Date? {
        Self.date(nextRunAt)
    }

    public var lastRunDate: Date? {
        Self.date(lastRunAt)
    }

    /// Parses a Hermes ISO-8601 timestamp, including Python's six-digit microseconds.
    public static func date(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let normalized = truncateFraction(iso)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: normalized) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: normalized)
    }

    /// `ISO8601DateFormatter` accepts three fractional digits; Python writes six.
    private static func truncateFraction(_ value: String) -> String {
        guard let dot = value.firstIndex(of: ".") else { return value }
        var end = value.index(after: dot)
        while end < value.endIndex, value[end].isNumber {
            end = value.index(after: end)
        }
        let fraction = value[value.index(after: dot) ..< end]
        guard fraction.count > 3 else { return value }
        let keep = value.index(dot, offsetBy: 4)
        return String(value[..<keep]) + String(value[end...])
    }

    /// Parses one job record; unknown or incomplete records are skipped.
    public static func parse(_ raw: JSONValue) -> CronJob? {
        guard let id = raw["id"]?.stringValue, !id.isEmpty else { return nil }
        let schedule = raw["schedule"]
        let repeatInfo = raw["repeat"]
        let enabled = raw["enabled"]?.boolValue
        let state = raw["state"]?.stringValue ?? (enabled == false ? "paused" : "scheduled")
        return CronJob(
            id: id,
            name: raw["name"]?.stringValue ?? id,
            prompt: raw["prompt"]?.stringValue ?? "",
            scheduleDisplay: raw["schedule_display"]?.stringValue
                ?? schedule?["display"]?.stringValue ?? "",
            scheduleKind: schedule?["kind"]?.stringValue,
            scheduleMinutes: schedule?["minutes"]?.intValue,
            scheduleExpression: schedule?["expr"]?.stringValue,
            runAt: schedule?["run_at"]?.stringValue,
            state: state,
            isEnabled: enabled ?? (state != "paused"),
            nextRunAt: raw["next_run_at"]?.stringValue,
            lastRunAt: raw["last_run_at"]?.stringValue,
            lastStatus: raw["last_status"]?.stringValue,
            lastError: raw["last_error"]?.stringValue,
            deliver: raw["deliver"]?.stringValue,
            timezone: raw["timezone"]?.stringValue,
            repeatTimes: repeatInfo?["times"]?.intValue,
            repeatCompleted: repeatInfo?["completed"]?.intValue
        )
    }
}
