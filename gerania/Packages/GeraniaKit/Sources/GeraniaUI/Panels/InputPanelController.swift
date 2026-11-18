import AppKit
import GeraniaCore
import HermesKit
import SwiftUI

/// Owns the mini window with the text input.
///
/// The panel accepts the key window, so the user can type into it, but the application
/// itself is never activated: the focus returns to the app that was active before.
@MainActor
public final class InputPanelController: NSObject, NSWindowDelegate {
    private let chats: ChatsModel
    private let model = InputViewModel()

    private var panel: FloatingPanel?
    private var previousApp: NSRunningApplication?
    private var isVisible = false
    /// Defer size changes until the SwiftUI layout pass is over.
    private let heightScheduler = PanelResizeScheduler()
    private let widthScheduler = PanelResizeScheduler()

    /// Called when the user sends the text: the flag tells a new chat from the current one.
    public var onSend: ((String, Bool) -> Void)?
    /// Called when the user picks a chat.
    public var onSelectChat: ((String) -> Void)?
    /// Called when the user starts a new chat.
    public var onNewChat: (() -> Void)?
    /// Called when the user presses the microphone button.
    public var onPushToTalk: (() -> Void)?
    /// Called when the user asks to rename a session.
    public var onRename: ((SessionSummary) -> Void)?
    /// Called when the user asks to open a session in the Hermes Desktop.
    public var onOpenInDesktop: ((String) -> Void)?

    public init(chats: ChatsModel) {
        self.chats = chats
        super.init()
        wireModel()
    }

    /// Shows the bottom window and moves the focus into the text field.
    public func show(prefill: String = "", showChats: Bool = false) {
        ensurePanel()
        previousApp = NSWorkspace.shared.frontmostApplication
        model.text = prefill
        model.focusToken += 1
        if showChats {
            model.openChatList()
        }
        isVisible = true
        model.isVisible = false
        panel?.alphaValue = 1
        panel?.makeKeyAndOrderFront(nil)
        resizeWidth(to: model.preferredWidth, animated: false)
        position()
        // Let the hosting view enter the window first, otherwise the spring has
        // nothing to animate from.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self, self.isVisible else { return }
            withAnimation(self.reduceMotion ? nil : self.appearAnimation) {
                self.model.isVisible = true
            }
        }
        Log.ui.info("input panel shown")
    }

    /// Hides the mini window and gives the focus back to the previous application.
    public func hide(animated: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        chats.closeList()
        guard let panel else { return }
        guard animated, !reduceMotion else {
            model.isVisible = false
            panel.orderOut(nil)
            restoreFocus()
            return
        }
        // The glass sinks towards the Dock, the window leaves the screen after it.
        withAnimation(disappearAnimation) {
            model.isVisible = false
        }
        restoreFocus()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !self.isVisible else { return }
            self.panel?.orderOut(nil)
        }
    }

    /// Sends synthetic key events to the panel and logs the state of the field.
    ///
    /// Used by the debug route `gerania://debug/type`: it checks that the keyboard
    /// really reaches the field and that the text is visible.
    public func simulateTyping(_ text: String) {
        guard let panel else { return }
        for character in text {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: String(character),
                charactersIgnoringModifiers: String(character),
                isARepeat: false,
                keyCode: 0
            ) else { continue }
            panel.sendEvent(event)
        }
        let responder = String(describing: panel.firstResponder)
        let field = panel.firstResponder as? NSTextField
        let editor = field?.currentEditor()
        let value = field?.stringValue ?? ""
        let editorValue = editor?.string ?? ""
        let probe = "type probe responder \(responder) value \(value) "
            + "editor \(editorValue) model \(model.text)"
        Log.ui.info("\(probe, privacy: .public)")
    }

    public func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func wireModel() {
        model.onSend = { [weak self] text, isNewChat in
            guard let self else { return }
            self.onSend?(text, isNewChat)
            self.hide()
        }
        model.onClose = { [weak self] in
            self?.hide()
        }
        model.onOpenChatList = { [weak self] in
            guard let self else { return }
            Task { await self.chats.openList() }
        }
        model.onNewChat = { [weak self] in
            self?.onNewChat?()
        }
        model.onSelectChat = { [weak self] id in
            self?.onSelectChat?(id)
        }
        model.onPushToTalk = { [weak self] in
            self?.onPushToTalk?()
        }
        model.onRename = { [weak self] session in
            self?.onRename?(session)
        }
        model.onOpenInDesktop = { [weak self] sessionID in
            self?.onOpenInDesktop?(sessionID)
        }
        model.onHeightChange = { [weak self] height in
            self?.heightScheduler.submit(height) { [weak self] height in
                self?.resizeHeight(to: height)
            }
        }
        model.onWidthChange = { [weak self] width in
            self?.widthScheduler.submit(width) { [weak self] width in
                self?.resizeWidth(to: width, animated: false)
            }
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = FloatingPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: InputViewModel.baseWidth,
                height: InputViewModel.baseHeight
            ),
            acceptsKey: true
        )
        panel.host(card)
        panel.delegate = self
        panel.onEscape = { [weak self] in
            self?.hide()
        }
        self.panel = panel
    }

    private var card: some View {
        InputCard(model: model, chats: chats)
    }

    private var appearAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.76)
    }

    private var disappearAnimation: Animation {
        .spring(response: 0.32, dampingFraction: 0.86)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func position() {
        guard let panel, let screen = PanelPlacement.screen(containing: NSEvent.mouseLocation) else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = PanelPlacement.bottomCenterOrigin(
            panelSize: size,
            screen: ScreenGeometry(screen: screen),
            margin: InputDesign.bottomMargin
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        let text = "input frame \(NSStringFromRect(panel.frame)) visible \(NSStringFromRect(visible))"
        Log.ui.info("\(text, privacy: .public)")
    }

    /// Keeps the bottom edge in place while the field or the chat picker grows.
    private func resizeHeight(to height: CGFloat) {
        guard let panel else { return }
        let targetHeight = max(height, 1)
        let current = panel.frame
        guard abs(current.height - targetHeight) > 0.5 else { return }
        let target = CGRect(
            x: current.origin.x,
            y: current.minY,
            width: current.width,
            height: targetHeight
        )
        panel.setFrame(target, display: true)
        Log.ui.info("input resized \(NSStringFromRect(target), privacy: .public)")
    }

    /// Widens the window while the text grows, keeping it centred and bottom-anchored.
    private func resizeWidth(to width: CGFloat, animated: Bool) {
        guard let panel, let screen = PanelPlacement.screen(containing: NSEvent.mouseLocation) else { return }
        let current = panel.frame
        guard abs(current.width - width) > 0.5 else { return }
        let visible = screen.visibleFrame
        let targetX = PanelPlacement.clampedX(
            visible.midX - width / 2,
            width: width,
            screen: visible
        )
        let target = CGRect(
            x: targetX,
            y: current.minY,
            width: width,
            height: current.height
        )
        guard animated else {
            panel.setFrame(target, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
    }

    /// Gives the focus back to the application that was active before the window.
    private func restoreFocus() {
        guard let previousApp, NSWorkspace.shared.frontmostApplication != previousApp else { return }
        previousApp.activate(options: [.activateIgnoringOtherApps])
    }
}
