import AppKit
import GeraniaCore
import SwiftUI

/// Окно приложения: приветствие, кнопка запуска и все настройки.
///
/// Это обычное окно, а не панель: Геря живёт в меню-баре, но запускается как
/// обычная программа — с иконкой в Dock и меню приложения.
@MainActor
public final class MainWindowController {
    /// Name of the saved frame of the window.
    private static let frameName = "GeraniaMainWindow"

    private let model: AppModel
    private let chats: ChatsModel
    private var window: NSWindow?

    public init(model: AppModel, chats: ChatsModel) {
        self.model = model
        self.chats = chats
    }

    /// Показывает окно и поднимает приложение.
    public func show() {
        let window = self.window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.ui.info("main window shown")
    }

    /// Убирает окно: приложение продолжает работать в фоне.
    public func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Гера"
        window.isReleasedWhenClosed = false
        self.window = window
        window.contentView = NSHostingView(
            rootView: MainWindowView(
                model: model,
                chats: chats,
                onLaunch: { [weak self] in self?.launch() },
                onStop: { [weak self] in self?.stop() },
                onLoadingFinished: { [weak self] in self?.setLoading(false) }
            )
        )
        // Пока играет анимация, шапка окна чёрная и без кнопок.
        setLoading(true)
        // Рамка: сохранённая пользователем или по центру экрана.
        if !window.setFrameUsingName(Self.frameName) {
            centerOnScreen(window)
        }
        window.setFrameAutosaveName(Self.frameName)
        return window
    }

    /// Black title bar without buttons while the loading animation plays.
    private func setLoading(_ loading: Bool) {
        guard let window else { return }
        window.titlebarAppearsTransparent = loading
        window.titleVisibility = loading ? .hidden : .visible
        window.backgroundColor = loading ? .black : nil
        for button in [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton),
        ] {
            button?.isHidden = loading
        }
    }

    /// Ставит окно в центр видимой области экрана.
    private func centerOnScreen(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
        window.setFrame(frame, display: false)
    }

    /// Запускает Герю и убирает окно: дальше всё идёт из меню-бара.
    private func launch() {
        Task { @MainActor in
            await model.startGera()
            guard model.isVoiceRunning else { return }
            hide()
        }
    }

    private func stop() {
        Task { @MainActor in
            await model.stopGera()
        }
    }
}
