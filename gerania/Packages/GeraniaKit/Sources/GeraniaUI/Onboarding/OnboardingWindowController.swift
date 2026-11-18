import AppKit
import GeraniaCore
import SwiftUI

/// The window of the first-run wizard.
///
/// It opens instead of the main window on the very first launch and again from
/// «Мастер настройки…» in the menu bar. Closing it with the red button counts
/// as «later»: the flag stays unset and the wizard returns on the next launch.
@MainActor
public final class OnboardingWindowController {
    private let model: OnboardingModel
    private var window: NSWindow?

    init(model: OnboardingModel) {
        self.model = model
    }

    public func show() {
        let window = self.window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.ui.info("onboarding shown")
    }

    public func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройка Геры"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(model: model))
        window.center()
        self.window = window
        return window
    }
}
