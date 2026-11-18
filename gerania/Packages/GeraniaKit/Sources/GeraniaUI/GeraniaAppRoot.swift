import Foundation
import GeraniaCore
import HermesKit
import KeyboardShortcuts
@preconcurrency import UserNotifications

/// Entry point the thin `@main` app target talks to.
@MainActor
public final class GeraniaAppRoot {
    public static let shared = GeraniaAppRoot()

    public let model: AppModel
    public let panels: PanelCoordinator
    public let hud: HUDViewModel
    public let chats: ChatsModel
    /// The window of the application: the welcome screen and the settings.
    public let mainWindow: MainWindowController
    /// Finished plans and the health of the Hermes scheduler.
    public let cronMonitor: CronMonitor

    private init() {
        let settings = GeraSettings()
        let hud = HUDViewModel()
        let chats = ChatsModel(settings: settings)
        self.hud = hud
        self.chats = chats
        model = AppModel(settings: settings, hud: hud, chats: chats)
        panels = PanelCoordinator(settings: settings, hud: hud, chats: chats)
        mainWindow = MainWindowController(model: model, chats: chats)
        cronMonitor = CronMonitor(directory: CronJobsStore.defaultDirectory())
        model.panels = panels
        chats.attach(service: model)
        panels.onSendPrompt = { [weak model] text, isNewChat in
            if isNewChat {
                model?.chats.newChat()
            }
            model?.ask(text)
        }
        panels.onSelectChat = { [weak model] id in
            model?.chats.select(sessionID: id)
        }
        panels.onNewChat = { [weak model] in
            model?.chats.newChat()
        }
        panels.onPushToTalk = { [weak model] in
            model?.pushToTalk()
        }
        panels.onHUDVisibilityChanged = { [weak model] visible in
            if !visible {
                model?.hudDidHide()
            }
        }
        panels.onRename = { [weak model] session in
            Task { await model?.renameChat(session) }
        }
        panels.onOpenInDesktop = { [weak model] sessionID in
            model?.openInDesktop(sessionID: sessionID)
        }
        registerShortcuts()
        startChatsRefresh()
        startCronMonitor()
    }

    /// Banners and HUD cards for plans that Hermes ran in the background.
    private func startCronMonitor() {
        UNUserNotificationCenter.current().delegate = CronNotificationDelegate.shared
        model.notificationRequest = {
            _ = await CronNotifier.requestIfNeeded()
        }
        cronMonitor.onResults = { [weak model] results in
            model?.announceCronResults(results)
        }
        cronMonitor.start()
    }

    /// Keeps the list of chats fresh for the menu bar.
    private func startChatsRefresh() {
        Task { @MainActor [weak model] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await model?.chats.refresh()
            }
        }
    }

    /// Global shortcuts of the application.
    private func registerShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .openInput) { [weak model] in
            Task { @MainActor in model?.openInput() }
        }
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak model] in
            Task { @MainActor in model?.pushToTalk() }
        }
        KeyboardShortcuts.onKeyDown(for: .stopAll) { [weak model] in
            Task { @MainActor in model?.stop() }
        }
    }
}
