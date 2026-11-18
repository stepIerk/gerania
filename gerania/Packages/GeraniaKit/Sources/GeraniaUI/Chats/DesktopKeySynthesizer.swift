import AppKit
import HermesKit

/// Sends the session id to the Hermes Desktop as key presses.
///
/// This is the experimental way: it needs the Accessibility permission and only works
/// when the Desktop is in front.
@MainActor
public enum DesktopKeySynthesizer {
    /// Types ⌘K, pastes the id and presses ⏎.
    public static func pasteSessionID(_ sessionID: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sessionID, forType: .string)

        press(key: 40, command: true) // ⌘K
        usleep(200_000)
        press(key: 9, command: true) // ⌘V
        usleep(200_000)
        press(key: 36) // ⏎
    }

    /// Sends one key press.
    private static func press(key: CGKeyCode, command: Bool = false) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) else { return }
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        if command {
            down.flags = .maskCommand
            up?.flags = .maskCommand
        }
        down.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
