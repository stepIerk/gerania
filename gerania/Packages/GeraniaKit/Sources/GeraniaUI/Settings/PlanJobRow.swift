import HermesKit
import SwiftUI

/// One row of the «Планы» list: schedule, state and the actions Hermes offers.
struct PlanJobRow: View {
    let job: CronJob
    let isBusy: Bool
    let onPause: () -> Void
    let onResume: () -> Void
    let onRun: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.name)
                        .font(.system(size: 12, weight: .medium))
                    Text(job.scheduleText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                badge
            }
            if !job.prompt.isEmpty {
                Text(job.prompt)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                if job.isPaused {
                    Button("Возобновить", action: onResume)
                } else if !job.isCompleted {
                    Button("На паузу", action: onPause)
                }
                if !job.isCompleted {
                    Button("Запустить сейчас", action: onRun)
                }
                Spacer(minLength: 0)
                Button("Удалить", role: .destructive, action: onDelete)
            }
            .font(.system(size: 10.5))
            .buttonStyle(.borderless)
            .disabled(isBusy)
            if let next = job.nextRunDate, !job.isPaused, !job.isCompleted {
                Text("Следующий запуск: \(next.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            if let last = job.lastRunDate {
                Text("Последний запуск: \(last.formatted(date: .abbreviated, time: .shortened))\(lastStatusSuffix)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            if let error = job.lastError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            if let held = job.lastFireError, !held.isEmpty {
                warning("Hermes отложил запуск: \(held)")
            } else if job.isOverdue() {
                warning("Время запуска прошло, а Hermes его не выполнил: проверьте планировщик выше.")
            }
        }
        .padding(.vertical, 3)
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 10.5))
            .foregroundStyle(.orange)
            .lineLimit(3)
    }

    private var badge: some View {
        Text(job.stateText)
            .font(.system(size: 9.5, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(badgeColor.opacity(0.15))
            }
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        if job.isCompleted {
            return .secondary
        }
        if job.isPaused {
            return .orange
        }
        return job.state == "error" ? .red : .green
    }

    private var lastStatusSuffix: String {
        guard let status = job.lastStatus, !status.isEmpty else { return "" }
        let label: String = switch status {
        case "success", "ok": "успешно"
        case "error", "failed": "ошибка"
        default: status
        }
        return " · \(label)"
    }
}
