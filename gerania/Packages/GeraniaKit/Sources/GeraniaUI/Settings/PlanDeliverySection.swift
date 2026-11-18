import HermesKit
import SwiftUI

/// Whether a plan can fire and reach the person: the Hermes scheduler and the
/// notification permission. Shown above the list so a silent failure is visible.
struct PlanDeliverySection: View {
    let model: PlansModel

    var body: some View {
        Section("Доставка напоминаний") {
            statusRow(
                symbol: model.scheduler.isRunning ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                color: model.scheduler.isRunning ? .green : .orange,
                title: model.scheduler.title,
                detail: model.scheduler.detail
            ) {
                if !model.scheduler.isRunning {
                    Button("Запустить планировщик") {
                        Task { await model.startScheduler() }
                    }
                    .disabled(model.isBusy)
                }
            }
            statusRow(
                symbol: notificationSymbol,
                color: model.notifications == .allowed ? .green : .orange,
                title: "Уведомления",
                detail: model.notifications.text
            ) {
                switch model.notifications {
                case .notDetermined:
                    Button("Разрешить уведомления") {
                        Task { await model.requestNotifications() }
                    }
                case .denied:
                    Button("Открыть настройки") {
                        CronNotifier.openSystemSettings()
                    }
                default:
                    EmptyView()
                }
            }
            Text(
                "Результаты приходят, пока Гера запущена (окно можно закрыть, она остаётся в меню-баре). "
                    + "Если Гера была выключена, Hermes всё равно выполнит план, а уведомление придёт "
                    + "при следующем запуске."
            )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notificationSymbol: String {
        model.notifications == .allowed ? "bell.badge.fill" : "bell.slash"
    }

    private func statusRow<Action: View>(
        symbol: String,
        color: Color,
        title: String,
        detail: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            action()
        }
    }
}
