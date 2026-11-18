import AppKit
import Foundation
import GeraniaCore
@preconcurrency import UserNotifications

/// Whether macOS lets Gerania show notifications.
public enum NotificationAccess: Sendable, Equatable {
    case unknown
    case notDetermined
    case allowed
    case denied

    /// One line for the «Планы» tab.
    public var text: String {
        switch self {
        case .allowed:
            "Уведомления разрешены: о готовом плане сообщит баннер и карточка Геры."
        case .notDetermined:
            "Уведомления ещё не разрешены: нажмите «Разрешить уведомления»."
        case .denied:
            "Уведомления запрещены в системе: о готовом плане сообщит только карточка Геры, "
                + "пока приложение открыто. Разрешите их в Системных настройках → Уведомления → Gerania."
        case .unknown:
            "Не удалось узнать, разрешены ли уведомления."
        }
    }
}

/// System notifications about finished plans.
///
/// Every call is `nonisolated`: the notification center answers on its own
/// queue, and only `Sendable` values cross back to the caller.
enum CronNotifier {
    static let pathKey = "cronOutputPath"

    static func access() async -> NotificationAccess {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        default:
            return .unknown
        }
    }

    /// Asks once; a later call after a refusal only reports the state.
    @discardableResult
    static func requestIfNeeded() async -> NotificationAccess {
        let current = await access()
        guard current == .notDetermined else { return current }
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            Log.ui.info("notifications granted: \(granted, privacy: .public)")
            return granted ? .allowed : .denied
        } catch {
            Log.ui.error("notification request failed: \(error.localizedDescription, privacy: .public)")
            return .unknown
        }
    }

    /// Posts one banner; a click opens `file`.
    static func post(identifier: String, title: String, body: String, file: URL?) async {
        guard await access() == .allowed else {
            Log.ui.info("cron notification skipped: not allowed")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "gerania.cron"
        if let file {
            content.userInfo = [pathKey: file.path]
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Log.ui.error("cron notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// System Settings → Notifications, for the «Открыть настройки» button.
    @MainActor
    static func openSystemSettings() {
        let link = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Shows banners while Gerania is in front and opens the result on click.
///
/// Without a delegate macOS hides the banner of the frontmost app, and Gerania
/// is an ordinary app that is often in front. The class keeps no state.
final class CronNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = CronNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let path = info[CronNotifier.pathKey] as? String else { return }
        let url = URL(fileURLWithPath: path)
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }
}
