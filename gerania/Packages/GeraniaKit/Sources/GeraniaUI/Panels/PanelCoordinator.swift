import Foundation
import GeraniaCore
import HermesKit

/// Owns the window layer and translates orchestrator events into panel actions.
///
/// Controllers are created lazily so no `NSWindow` exists before the app is ready.
@MainActor
public final class PanelCoordinator: PanelPresenting {
    /// Called when the user sends the text from the mini window.
    public var onSendPrompt: ((String, Bool) -> Void)?
    /// Called when the user asks to rename a session.
    public var onRename: ((SessionSummary) -> Void)?
    /// Called when the user asks to open a session in the Hermes Desktop.
    public var onOpenInDesktop: ((String) -> Void)?
    /// Called when the user picks a chat.
    public var onSelectChat: ((String) -> Void)?
    /// Called when the user starts a new chat.
    public var onNewChat: (() -> Void)?
    /// Called when the user presses the microphone button.
    public var onPushToTalk: (() -> Void)?
    /// Called when the HUD panel appears or disappears.
    public var onHUDVisibilityChanged: ((Bool) -> Void)?

    private let settings: GeraSettings
    private let hudModel: HUDViewModel
    private let chats: ChatsModel
    private var hudController: HUDPanelController?
    private var inputController: InputPanelController?
    private var detailController: DetailPanelController?

    public init(settings: GeraSettings, hud: HUDViewModel, chats: ChatsModel) {
        self.settings = settings
        hudModel = hud
        self.chats = chats
    }

    public func presentHUD(state: GeraState) {
        hud().show(state: state)
    }

    public func updateHUD(state: GeraState) {
        hud().update(state: state)
    }

    public func dismissHUD(after delay: TimeInterval) {
        hud().hide(after: delay)
    }

    public func presentInput(prefill: String = "", showChats: Bool = false) {
        input().show(prefill: prefill, showChats: showChats)
    }

    public func presentDetail() {
        if detailController == nil {
            detailController = DetailPanelController(model: hudModel, settings: settings)
        }
        detailController?.show()
    }

    public func dismissDetail() {
        detailController?.hide()
    }

    /// Sends synthetic keystrokes to the mini window — used by the debug route.
    public func simulateTyping(_ text: String) {
        inputController?.simulateTyping(text)
    }

    /// Frame of the HUD, but only when it is really on screen.
    private var visibleHUDFrame: CGRect? {
        guard hudController?.isPanelVisible == true else { return nil }
        return hudController?.panelFrame
    }

    private func hud() -> HUDPanelController {
        if let hudController {
            return hudController
        }
        let created = HUDPanelController(settings: settings, model: hudModel)
        created.onVisibilityChanged = { [weak self] visible in
            self?.onHUDVisibilityChanged?(visible)
        }
        hudController = created
        return created
    }

    private func input() -> InputPanelController {
        if let inputController {
            return inputController
        }
        let created = InputPanelController(chats: chats)
        created.onSend = { [weak self] text, isNewChat in
            self?.onSendPrompt?(text, isNewChat)
        }
        created.onRename = { [weak self] session in
            self?.onRename?(session)
        }
        created.onOpenInDesktop = { [weak self] sessionID in
            self?.onOpenInDesktop?(sessionID)
        }
        created.onSelectChat = { [weak self] id in
            self?.onSelectChat?(id)
        }
        created.onNewChat = { [weak self] in
            self?.onNewChat?()
        }
        created.onPushToTalk = { [weak self] in
            self?.onPushToTalk?()
        }
        inputController = created
        return created
    }
}
