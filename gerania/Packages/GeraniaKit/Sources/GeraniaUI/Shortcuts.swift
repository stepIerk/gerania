import AppKit
import KeyboardShortcuts

/// Global shortcuts of Gerania.
public extension KeyboardShortcuts.Name {
    /// Opens the mini window with the text input.
    static let openInput = Self(
        "gerania.openInput",
        default: .init(.space, modifiers: [.control, .option])
    )

    /// Talk: a tap works like «Гера», holding keeps the microphone open until release.
    static let pushToTalk = Self(
        "gerania.pushToTalk",
        default: .init(.g, modifiers: [.control, .option])
    )

    /// Stops the answer: the speech and the running turn.
    static let stopAll = Self(
        "gerania.stopAll",
        default: .init(.g, modifiers: [.control, .option, .shift])
    )

    /// Turns the microphone off and on.
    static let toggleMicrophone = Self(
        "gerania.toggleMicrophone",
        default: .init(.g, modifiers: [.control, .option, .command])
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
