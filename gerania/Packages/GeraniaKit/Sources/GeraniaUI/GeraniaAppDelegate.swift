import AppKit
import GeraniaCore

/// AppKit glue: the activation policy, the window of the application and `gerania://`
/// URLs delivered by Launch Services.
@MainActor
public final class GeraniaAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Gera lives in the menu bar, but it is an ordinary application: it has an
        // icon in the Dock, a menu of its own and ⌘Q.
        NSApp.setActivationPolicy(.regular)
        Log.app.info("Gerania launched")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let debug = self.applyLaunchArguments()
            guard !debug else { return }
            Task { @MainActor in
                await self.startUp()
            }
        }
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            GeraniaAppRoot.shared.model.handle(url: url)
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        GeraniaAppRoot.shared.mainWindow.show()
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Launched by a human: the window of the application opens (inside it plays the
    /// animation of the loading screen) and the voice waits for the button. Launched at
    /// login: the voice starts quietly, the window does not appear.
    private func startUp() async {
        let model = GeraniaAppRoot.shared.model
        if LaunchOrigin.isLoginItem, model.settings.launchAtLogin {
            Log.app.info("launched at login: no window, voice only")
            await model.startVoice()
            return
        }
        GeraniaAppRoot.shared.mainWindow.show()
    }

    /// `--gera-debug-state=<name>` and `--gera-debug-input` open the panels from the
    /// command line. Used by `scripts/smoke.sh` while the URL scheme is not registered.
    ///
    /// Returns `true` when the launch was a debug one: then the app window stays closed.
    @discardableResult
    private func applyLaunchArguments() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let prefix = "--gera-debug-state="
        let streamPrefix = "--gera-debug-stream="
        var debug = false
        for argument in arguments {
            if argument.hasPrefix(prefix) {
                debug = true
                let name = String(argument.dropFirst(prefix.count))
                GeraniaAppRoot.shared.model.showDebugState(named: name)
            } else if argument == "--gera-debug-input" {
                debug = true
                GeraniaAppRoot.shared.model.openInput()
            } else if argument == "--gera-debug-input-text" {
                debug = true
                GeraniaAppRoot.shared.model.openInput(
                    prefill: "Первая строка\nВторая строка\nТретья строка"
                )
            } else if argument == "--gera-debug-input-chats" {
                debug = true
                GeraniaAppRoot.shared.model.openInput(showChats: true)
            } else if argument.hasPrefix(streamPrefix) {
                debug = true
                let name = String(argument.dropFirst(streamPrefix.count))
                GeraniaAppRoot.shared.model.playFixture(named: name)
            } else if argument == "--gera-no-window" {
                // Отладочный запуск: окно приложения не нужно, только панели.
                debug = true
            }
        }
        return debug
    }
}
