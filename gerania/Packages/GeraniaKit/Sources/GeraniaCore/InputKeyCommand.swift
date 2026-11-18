import Foundation

/// Logical key of the mini window, independent of the physical keyboard layout.
public enum InputKey: Equatable, Sendable {
    case returnKey
    case escape
    case up
    case down
    case character(String)
}

/// Command the mini window performs for a key press.
public enum InputKeyCommand: Equatable, Sendable {
    /// Send the text.
    case send
    /// Send the text in a new chat.
    case sendInNewChat
    /// Insert a line break.
    case newline
    /// Close the mini window.
    case close
    /// Show the previous prompt from the history.
    case previousPrompt
    /// Show the next prompt from the history.
    case nextPrompt
    /// Open the list of chats.
    case openChatList
    /// Start a new chat.
    case newChat
    /// The key is not a command.
    case none
}

/// Turns a key press into a command of the mini window.
///
/// The logic lives outside the view so it can be tested without a window.
public enum InputKeyParser {
    /// Parses the key press.
    public static func command(
        for key: InputKey,
        shift: Bool = false,
        command: Bool = false,
        option: Bool = false
    ) -> InputKeyCommand {
        switch key {
        case .returnKey:
            if command {
                return .sendInNewChat
            }
            if shift {
                return .newline
            }
            return .send
        case .escape:
            return .close
        case .up:
            return .previousPrompt
        case .down:
            return .nextPrompt
        case let .character(character):
            let normalized = character.lowercased()
            if command, normalized == "k" {
                return .openChatList
            }
            if command, normalized == "n" {
                return .newChat
            }
            return .none
        }
    }
}
