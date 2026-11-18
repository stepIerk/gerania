import AppKit
import Foundation
import GeraniaCore
import HermesKit

/// The part of the orchestrator that works with the chats.
extension AppModel: ChatsService {
    public var supportsRenaming: Bool {
        false
    }

    /// Whether the active transport can rename a session.
    public func canRenameSessions() async -> Bool {
        guard let manager = transport else { return false }
        return await manager.supportsRenaming()
    }

    public func listSessions() async -> [SessionSummary] {
        await chatSessions()
    }

    public func renameSession(id: String, title: String) async throws {
        let manager = try await makeTransport()
        try await manager.renameSession(id: id, title: title)
    }

    /// Renames the chat through the official method of the protocol.
    public func renameChat(_ session: SessionSummary) async {
        await chats.rename(sessionID: session.id, title: session.title)
    }

    /// Opens the session in the Hermes Desktop.
    public func openInDesktop(sessionID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.launchDesktop(sessionID: sessionID)
        }
    }

    /// Opens the session in a terminal with `hermes --resume`.
    public func openInTerminal(sessionID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let app: TerminalLauncher.TerminalApp = switch self.settings.terminalApp {
            case .terminal: .terminal
            case .iTerm: .iTerm
            }
            let result = await TerminalLauncher().open(sessionID: sessionID, app: app)
            if case let .failure(failure) = result {
                self.showHint(failure.localizedDescription)
            }
        }
    }

    /// Shows a short hint in the HUD.
    func showHint(_ text: String) {
        hud.hint = text
        hud.hintExpiresAt = Date().addingTimeInterval(6)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self else { return }
            if self.hud.hint == text {
                self.hud.hint = nil
                self.hud.hintExpiresAt = nil
            }
        }
    }

    private func launchDesktop(sessionID: String) async {
        let capabilities = DesktopEnvironment.capabilities()
        let strategy = DesktopLauncher.strategy(
            for: capabilities,
            allowsKeySynthesis: settings.experimentalDesktopKeys
        )
        let launcher = DesktopLauncher()
        let outcome = await launcher.open(
            sessionID: sessionID,
            strategy: strategy,
            capabilities: capabilities
        )
        switch outcome {
        case let .opened(used):
            Log.hermes.info("session opened in Hermes Desktop via \(used.rawValue, privacy: .public)")
        case .needsPaste:
            showHint("Скопировал ID сессии — вставьте его в Desktop: ⌘K → ⌘V → ⏎")
            if strategy == .synthesizeKeys {
                DesktopKeySynthesizer.pasteSessionID(sessionID)
            } else {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(sessionID, forType: .string)
            }
        case let .failed(message):
            showHint(message)
        }
    }
}
