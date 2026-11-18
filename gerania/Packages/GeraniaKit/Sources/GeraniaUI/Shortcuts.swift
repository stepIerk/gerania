import AppKit
import KeyboardShortcuts

/// Global shortcuts of Gerania.
public extension KeyboardShortcuts.Name {
    /// Opens the mini window with the text input.
    static let openInput = Self(
        "gerania.openInput",
        default: .init(.space, modifiers: [.control, .option])
    )

    /// Push to talk: behaves like the wake word.
    static let pushToTalk = Self(
        "gerania.pushToTalk",
        default: .init(.v, modifiers: [.control, .option])
    )

    /// Interrupts the current turn and stops the speech.
    static let stopAll = Self(
        "gerania.stopAll",
        default: .init(.period, modifiers: [.control, .option])
    )
}

/// Shortcuts that macOS keeps for itself.
///
/// Such a combination is never delivered to the app, so the recorder has to warn the
/// user before they wonder why nothing happens.
public enum SystemShortcutConflict {
    /// Combinations reserved by the system.
    public static let reserved: [KeyboardShortcuts.Shortcut] = [
        .init(.space, modifiers: [.command]),
        .init(.space, modifiers: [.control, .option]),
        .init(.space, modifiers: [.control]),
        .init(.space, modifiers: [.command, .option]),
        .init(.tab, modifiers: [.command]),
        .init(.period, modifiers: [.command]),
        .init(.comma, modifiers: [.command]),
        .init(.v, modifiers: [.command, .control]),
        .init(.v, modifiers: [.command, .option]),
        .init(.v, modifiers: [.command]),
    ]

    /// Returns the reserved combination that clashes with the given shortcut.
    public static func conflict(for shortcut: KeyboardShortcuts.Shortcut?) -> KeyboardShortcuts.Shortcut? {
        guard let shortcut else { return nil }
        return reserved.first { $0 == shortcut }
    }

    /// Human readable name of the reserved combination.
    @MainActor
    public static func describe(_ shortcut: KeyboardShortcuts.Shortcut) -> String {
        shortcut.description
    }
}
