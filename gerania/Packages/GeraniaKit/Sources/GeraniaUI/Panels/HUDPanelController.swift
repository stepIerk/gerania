import AppKit
import GeraniaCore
import SwiftUI

/// Owns the floating HUD panel.
///
/// The panel appears above other applications without activating Gerania. It does not
/// become key by itself, but a click makes it key (the panel is non-activating), so its
/// buttons work without switching apps. The approval card asks for the key window
/// explicitly to receive ⏎ and Esc.
@MainActor
public final class HUDPanelController {
    let settings: GeraSettings
    let model: HUDViewModel

    var panel: FloatingPanel?
    /// Called when the panel appears or disappears.
    var onVisibilityChanged: ((Bool) -> Void)?
    var observers: [NSObjectProtocol] = []
    var pendingHeight: CGFloat?
    var lastResizeAt = Date.distantPast
    var resizeTask: Task<Void, Never>?
    /// Defers height changes until the SwiftUI layout pass is over.
    let resizeScheduler = PanelResizeScheduler()

    private var autoHideTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var autoHideDelay: TimeInterval?
    private var isHovering = false
    private var isVisible = false

    public init(settings: GeraSettings, model: HUDViewModel) {
        self.settings = settings
        self.model = model
    }

    /// Whether the HUD is on screen right now.
    public var isPanelVisible: Bool {
        isVisible
    }

    /// Frame of the visible panel, used to place the input panel below the HUD.
    public var panelFrame: CGRect? {
        guard isVisible else { return nil }
        return panel?.frame
    }

    /// Shows the HUD panel in the given state.
    public func show(state: GeraState) {
        autoHideTask?.cancel()
        autoHideTask = nil
        hideTask?.cancel()
        hideTask = nil
        model.state = state
        ensurePanel()
        guard let panel else { return }
        if !isVisible {
            isVisible = true
            model.isVisible = false
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            // Let the hosting view enter the window first, otherwise the spring has
            // nothing to animate from.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, self.isVisible else { return }
                withAnimation(self.reduceMotion ? nil : self.appearAnimation) {
                    self.model.isVisible = true
                }
            }
            Log.ui.debug("hud panel shown")
            onVisibilityChanged?(true)
        }
        updateKeyBehavior(for: state)
        // `reposition` is idempotent: during streaming the panel is already in
        // place, so this is a cheap no-op instead of another `setFrame`.
        reposition()
    }

    /// Updates the content of the panel without touching the window order.
    public func update(state: GeraState) {
        model.state = state
        updateKeyBehavior(for: state)
    }

    /// Hides the panel, optionally with the disappearance animation.
    public func hide(animated: Bool = true) {
        autoHideTask?.cancel()
        autoHideTask = nil
        autoHideDelay = nil
        guard isVisible else { return }
        isVisible = false
        hideTask?.cancel()
        if animated, !reduceMotion {
            withAnimation(disappearAnimation) {
                model.isVisible = false
            }
            hideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.orderOut()
            }
        } else {
            model.isVisible = false
            orderOut()
        }
    }

    /// Hides the panel after the given delay unless the pointer hovers the panel.
    public func hide(after delay: TimeInterval) {
        guard !model.isPinned else { return }
        autoHideDelay = delay
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    /// Pauses the auto-hide timer while the pointer is over the panel.
    public func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        if hovering {
            autoHideTask?.cancel()
            autoHideTask = nil
        } else if let delay = autoHideDelay {
            hide(after: delay)
        }
    }

    func orderOut() {
        panel?.orderOut(nil)
        onVisibilityChanged?(false)
    }

    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var appearAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.76)
    }

    private var disappearAnimation: Animation {
        .spring(response: 0.32, dampingFraction: 0.86)
    }
}
