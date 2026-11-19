import Foundation
import GeraniaCore

/// Action requested by a button in the HUD.
public enum HUDAction: Sendable {
    /// Copy the answer to the pasteboard.
    case copyAnswer
    /// Continue the conversation in the mini window.
    case continueChat
    /// Show the full answer in a larger window.
    case expandAnswer
    /// Open the session in Hermes Desktop.
    case openInDesktop
    /// Open the session in a terminal.
    case openInTerminal
    /// Start or stop reading the answer aloud.
    case toggleSpeech
    /// Close the panel.
    case closePanel
    /// Pin the panel so it does not hide itself.
    case togglePin
    /// Repeat the failed request.
    case retry
    /// Answer an approval or clarification request.
    case answer(ServerRequest, ServerRequestAnswer)
    /// Stop the turn that is driving the computer.
    case stopComputerUse
    /// Stop the answer: the speech and the running turn.
    case stopAnswer
}
