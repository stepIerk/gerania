import Foundation
import GeraniaCore

/// Opens a session in the Hermes Desktop application.
///
/// The ways are tried in the order that Hermes itself supports (see `docs/HERMES_PROTOCOL.md`):
/// a deep link first, then the plain launch of the application, and only then the
/// experimental synthesis of key presses.
public struct DesktopLauncher: Sendable {
    /// The way the launcher will use.
    public enum Strategy: String, Sendable, Equatable, CaseIterable {
        /// `hermes://open/session/<id>` — the way Hermes Desktop itself registers.
        case deepLink
        /// Activate the session in the gateway and bring the Desktop to the front.
        case activateAndLaunch
        /// Launch the Desktop and put the session id into the clipboard.
        case openWithClipboard
        /// Experimental: type the session id into the Desktop.
        case synthesizeKeys
    }

    /// Terminal application used by «Открыть в Терминале».
    public enum TerminalApp: String, Sendable, Equatable, CaseIterable {
        case terminal
        case iTerm
    }

    /// What the machine can do.
    public struct Capabilities: Sendable, Equatable {
        /// The Desktop application is installed.
        public var isDesktopInstalled: Bool
        /// The Desktop application is running.
        public var isDesktopRunning: Bool
        /// The `hermes://` scheme is registered in the system.
        public var hasDeepLink: Bool
        /// The app is allowed to send synthetic key presses.
        public var isAccessibilityTrusted: Bool

        public init(
            isDesktopInstalled: Bool = true,
            isDesktopRunning: Bool = false,
            hasDeepLink: Bool = false,
            isAccessibilityTrusted: Bool = false
        ) {
            self.isDesktopInstalled = isDesktopInstalled
            self.isDesktopRunning = isDesktopRunning
            self.hasDeepLink = hasDeepLink
            self.isAccessibilityTrusted = isAccessibilityTrusted
        }
    }

    /// Result of an attempt to open the session.
    public enum Outcome: Sendable, Equatable {
        /// The session is open in the Desktop.
        case opened(Strategy)
        /// The Desktop was opened, the user has to paste the id by hand.
        case needsPaste(Strategy)
        /// Nothing worked, the message goes to the HUD.
        case failed(String)
    }

    public init() {}

    /// Scheme of the deep link of Hermes Desktop.
    public static let deepLinkScheme = "hermes"

    /// Deep link that opens the session in the Desktop.
    public static func deepLink(sessionID: SessionID) -> String {
        "\(deepLinkScheme)://open/session/\(sessionID)"
    }

    /// Picks the way to open the session.
    public static func strategy(
        for capabilities: Capabilities,
        allowsKeySynthesis: Bool
    ) -> Strategy {
        if capabilities.hasDeepLink {
            return .deepLink
        }
        if capabilities.isDesktopRunning {
            return .activateAndLaunch
        }
        if allowsKeySynthesis, capabilities.isAccessibilityTrusted {
            return .synthesizeKeys
        }
        return .openWithClipboard
    }

    /// Opens the session with the given strategy.
    ///
    /// The deep link and the plain launch are done through the `open` command, so the
    /// launcher stays free of AppKit.
    public func open(
        sessionID: SessionID,
        strategy: Strategy,
        capabilities: Capabilities
    ) async -> Outcome {
        switch strategy {
        case .deepLink:
            return await openDeepLink(sessionID: sessionID)
        case .activateAndLaunch:
            let launched = await openApplication()
            return launched ? .opened(strategy) : .failed("Hermes Desktop не запустился")
        case .openWithClipboard:
            let launched = await openApplication()
            guard launched else { return .failed("Hermes Desktop не запустился") }
            await copyToClipboard(sessionID)
            return .needsPaste(strategy)
        case .synthesizeKeys:
            let launched = await openApplication()
            guard launched else { return .failed("Hermes Desktop не запустился") }
            await copyToClipboard(sessionID)
            return .needsPaste(strategy)
        }
    }

    /// Opens the deep link of the session.
    public func openDeepLink(sessionID: SessionID) async -> Outcome {
        let ok = await run("/usr/bin/open", [Self.deepLink(sessionID: sessionID)])
        return ok ? .opened(.deepLink) : .failed("не удалось открыть hermes://")
    }

    /// Brings the Desktop application to the front.
    public func openApplication() async -> Bool {
        if await run("/usr/bin/open", ["-a", "Hermes"]) {
            return true
        }
        return await run("/usr/bin/open", ["-a", "Hermes.app"])
    }

    /// Puts the text into the clipboard.
    public func copyToClipboard(_ text: String) async {
        await run("/usr/bin/pbcopy", [], input: text)
    }

    private func run(_ path: String, _ arguments: [String], input: String? = nil) async -> Bool {
        guard let process = try? ChildProcess(
            executable: URL(fileURLWithPath: path),
            arguments: arguments,
            environment: BinaryLocator.live(homeDirectory: NSHomeDirectory()).environment(),
            currentDirectory: NSTemporaryDirectory()
        ) else {
            return false
        }
        if let input {
            try? process.stdin.write(contentsOf: Data(input.utf8))
            try? process.stdin.close()
        }
        let status = await process.wait()
        return status == 0
    }
}
