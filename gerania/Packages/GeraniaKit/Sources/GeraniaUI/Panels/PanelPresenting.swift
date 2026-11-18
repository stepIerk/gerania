import Foundation
import GeraniaCore

/// Contract between the orchestrator (`AppModel`) and the window layer.
@MainActor
public protocol PanelPresenting: AnyObject {
    /// Shows the HUD panel in the given state.
    func presentHUD(state: GeraState)
    /// Updates the content of an already visible HUD panel.
    func updateHUD(state: GeraState)
    /// Hides the HUD panel after the given delay.
    func dismissHUD(after delay: TimeInterval)
    /// Shows the text input panel.
    func presentInput(prefill: String, showChats: Bool)
    /// Shows the full answer in the large reading window.
    func presentDetail()
    /// Closes the large reading window, if it is open.
    func dismissDetail()
    /// Sends synthetic keystrokes to the input field — used by the debug route.
    func simulateTyping(_ text: String)
}

public extension PanelPresenting {
    func presentDetail() {}
    func dismissDetail() {}
    func simulateTyping(_ text: String) {}
}
