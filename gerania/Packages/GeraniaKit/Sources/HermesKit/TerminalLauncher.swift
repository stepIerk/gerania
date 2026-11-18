import Foundation

/// Opens a session in a terminal application.
///
/// The command is `hermes --resume <id>`; the id is quoted for the shell and the whole
/// command is escaped for the AppleScript string literal.
public struct TerminalLauncher: Sendable {
    /// Terminal application to use.
    public enum TerminalApp: String, Sendable, Equatable, CaseIterable {
        case terminal
        case iTerm

        /// Name of the application as AppleScript knows it.
        public var applicationName: String {
            switch self {
            case .terminal: "Terminal"
            case .iTerm: "iTerm"
            }
        }
    }

    public init() {}

    /// Failure of the launch.
    public enum Failure: Error, LocalizedError, Sendable, Equatable {
        case appleScript(String)
        case notInstalled(TerminalApp)

        public var errorDescription: String? {
            switch self {
            case let .appleScript(message): "Не удалось открыть терминал: \(message)"
            case let .notInstalled(app): "\(app.applicationName) не установлен"
            }
        }
    }

    /// Shell command that resumes the session.
    public static func command(sessionID: SessionID, hermesPath: String = "hermes") -> String {
        "\(hermesPath) --resume \(shellQuote(sessionID))"
    }

    /// AppleScript that runs the command in the terminal.
    public static func appleScript(
        sessionID: SessionID,
        app: TerminalApp = .terminal,
        hermesPath: String = "hermes"
    ) -> String {
        let command = escapeAppleScript(command(sessionID: sessionID, hermesPath: hermesPath))
        switch app {
        case .terminal:
            return """
            tell application "Terminal"
                activate
                do script "\(command)"
            end tell
            """
        case .iTerm:
            return """
            tell application "iTerm"
                activate
                if (count of windows) = 0 then
                    create window with default profile
                end if
                tell current session of current window
                    write text "\(command)"
                end tell
            end tell
            """
        }
    }

    /// Escapes a string for an AppleScript string literal.
    public static func escapeAppleScript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Quotes a value for the shell.
    public static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs the AppleScript.
    public func open(
        sessionID: SessionID,
        app: TerminalApp = .terminal,
        hermesPath: String = "hermes"
    ) async -> Result<String, Failure> {
        let script = Self.appleScript(sessionID: sessionID, app: app, hermesPath: hermesPath)
        var errorInfo: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "неизвестная ошибка"
            return .failure(.appleScript(message))
        }
        _ = result
        return .success(script)
    }
}
