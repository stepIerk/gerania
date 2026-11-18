import Foundation
import GeraniaCore
import HermesKit
import Testing

@Suite("DesktopLauncher")
struct DesktopLauncherTests {
    @Test("Deep link wins when the scheme is known")
    func deepLinkFirst() {
        let capabilities = DesktopLauncher.Capabilities(
            isDesktopInstalled: true,
            isDesktopRunning: true,
            hasDeepLink: true,
            isAccessibilityTrusted: true
        )

        #expect(
            DesktopLauncher.strategy(for: capabilities, allowsKeySynthesis: true) == .deepLink
        )
    }

    @Test("Без deep link запущенный Desktop активируется")
    func activateRunningDesktop() {
        let capabilities = DesktopLauncher.Capabilities(
            isDesktopInstalled: true,
            isDesktopRunning: true,
            hasDeepLink: false,
            isAccessibilityTrusted: false
        )

        #expect(
            DesktopLauncher.strategy(for: capabilities, allowsKeySynthesis: true) == .activateAndLaunch
        )
    }

    @Test("Экспериментальный ввод включается только с разрешением")
    func synthesizeOnlyWithPermission() {
        let allowed = DesktopLauncher.Capabilities(
            isDesktopInstalled: true,
            isDesktopRunning: false,
            hasDeepLink: false,
            isAccessibilityTrusted: true
        )
        let denied = DesktopLauncher.Capabilities(
            isDesktopInstalled: true,
            isDesktopRunning: false,
            hasDeepLink: false,
            isAccessibilityTrusted: false
        )

        #expect(
            DesktopLauncher.strategy(for: allowed, allowsKeySynthesis: true) == .synthesizeKeys
        )
        #expect(
            DesktopLauncher.strategy(for: denied, allowsKeySynthesis: true) == .openWithClipboard
        )
        #expect(
            DesktopLauncher.strategy(for: allowed, allowsKeySynthesis: false) == .openWithClipboard
        )
    }

    @Test("Deep link открывает сессию")
    func deepLinkFormat() {
        #expect(
            DesktopLauncher.deepLink(sessionID: "local-abc") == "hermes://open/session/local-abc"
        )
    }
}

@Suite("TerminalLauncher")
struct TerminalLauncherTests {
    @Test("Идентификатор сессии цитируется для шелла")
    func shellQuoting() {
        let command = TerminalLauncher.command(sessionID: "local-abc")

        #expect(command == "hermes --resume 'local-abc'")
    }

    @Test("Кавычки внутри идентификатора экранируются")
    func shellQuotingWithQuote() {
        let command = TerminalLauncher.command(sessionID: "it's")

        #expect(command == "hermes --resume 'it'\\''s'")
    }

    @Test("Скрипт экранирует кавычки и обратные слэши")
    func appleScriptEscaping() {
        let script = TerminalLauncher.appleScript(
            sessionID: "a\"b",
            app: .terminal
        )

        #expect(script.contains("do script \"hermes --resume 'a\\\"b'\""))
        #expect(script.contains("tell application \"Terminal\""))
    }

    @Test("Скрипт для iTerm создаёт окно")
    func itermScript() {
        let script = TerminalLauncher.appleScript(sessionID: "local-1", app: .iTerm)

        #expect(script.contains("tell application \"iTerm\""))
        #expect(script.contains("create window with default profile"))
    }
}
