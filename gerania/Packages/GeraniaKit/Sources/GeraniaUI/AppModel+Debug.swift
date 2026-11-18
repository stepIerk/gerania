import Foundation
import GeraniaCore

/// Debug routes and the `gerania://` URL scheme.
///
/// The scheme is the only way scripts and agents drive the app: there is no HTTP
/// server. Everything except the user routes is guarded by `isDebugEnabled`.
public extension AppModel {
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "gerania" else {
            Log.ui.debug("ignored URL scheme: \(url.scheme ?? "nil", privacy: .public)")
            return
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let host = components.host?.lowercased() ?? ""
        let path = components.path.lowercased()
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        Log.ui.info("handling \(url.absoluteString, privacy: .public)")

        switch (host, path) {
        case ("ask", _):
            ask(query["text"] ?? "")
        case ("input", _):
            openInput(prefill: query["text"] ?? "", showChats: query["chats"] == "1")
        case ("listen", _):
            dispatch(.wake(at: Date().timeIntervalSince1970))
        case ("start", _):
            Task { await startGera() }
        case ("stop", _):
            stop()
        case ("debug", "/state"):
            showDebugState(named: query["name"] ?? "thinking")
        case ("debug", "/stream"):
            playFixture(named: query["sample"] ?? "markdown")
        case ("debug", "/live"):
            guard isDebugEnabled else { return }
            startLiveDialog(seed: query["text"], waitForPhrase: false)
        case ("debug", "/detail"):
            guard isDebugEnabled else { return }
            panels?.presentDetail()
        case ("debug", "/type"):
            guard isDebugEnabled else { return }
            panels?.simulateTyping(query["text"] ?? "")
        case ("session", "/open"):
            if let id = query["id"] {
                settings.lastSessionID = id
                dispatch(.turnStarted)
            }
        default:
            Log.ui.debug("unknown route \(host, privacy: .public)\(path, privacy: .public)")
        }
    }

    /// Shows the HUD panel in the given state. Used by the debug routes.
    func showDebugState(named name: String) {
        guard isDebugEnabled else {
            Log.ui.info("debug routes are disabled in release")
            return
        }
        hud.reset()
        hud.heardText = nil
        switch name {
        case "listening":
            apply(state: .listening(deadline: Date().timeIntervalSince1970 + 8))
        case "heard":
            hud.heardText = "Гера, расскажи, что нового в Swift 6 и как работает strict concurrency"
            apply(state: .listening(deadline: Date().timeIntervalSince1970 + 8))
        case "thinking":
            let tools = [
                ToolChip(id: "debug-1", name: "terminal", detail: "date -u"),
                ToolChip(id: "debug-2", name: "web_search", detail: "swift 6 concurrency", isFinished: true),
                ToolChip(id: "debug-3", name: "browser_exec", detail: "open · example.com"),
            ]
            tools.forEach(hud.startTool)
            apply(state: .thinking(tools: tools))
        case "streaming":
            apply(state: .streaming)
        case "error":
            apply(state: .error("Тестовая ошибка"))
        case "done":
            apply(state: .done)
        default:
            apply(state: .idle)
        }
        panels?.presentHUD(state: state)
    }

    /// Plays a fixture as if the answer was streamed by Hermes.
    func playFixture(named name: String) {
        guard isDebugEnabled else {
            Log.ui.info("debug routes are disabled in release")
            return
        }
        guard let text = HUDFixture.text(named: name) else {
            Log.ui.info("unknown fixture \(name, privacy: .public)")
            return
        }
        cancelTurn()
        hud.reset()
        dispatch(.turnStarted)
        Task { [weak self] in
            await self?.streamFixture(text, named: name)
        }
    }

    internal var isDebugEnabled: Bool {
        #if DEBUG
            true
        #else
            ProcessInfo.processInfo.environment["GERA_DEBUG"] == "1"
        #endif
    }
}
