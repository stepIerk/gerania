import AppKit
import GeraniaCore
import SwiftUI

/// Window plumbing of the HUD panel: creation, placement and resizing.
extension HUDPanelController {
    /// Minimum interval between two frame changes (20 updates per second).
    static let resizeInterval: TimeInterval = 0.05

    /// Creates the panel and the hosting view on first use.
    func ensurePanel() {
        guard panel == nil else { return }
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: HUDTheme.width, height: HUDTheme.minHeight),
            acceptsKey: true
        )
        panel.host(HUDContent(model: model))
        panel.onEscape = { [weak self] in
            self?.hide(animated: true)
        }
        self.panel = panel
        model.onHeightChange = { [weak self] height in
            self?.requestHeight(height)
        }
        model.onHover = { [weak self] hovering in
            self?.setHovering(hovering)
        }
        observeScreenChanges()
    }

    /// The approval card asks for ⏎ and Esc, so the panel accepts the key window.
    /// For all other states the panel stays inert until the user clicks one of its
    /// buttons; `acceptsFirstMouse` in `PanelHost` delivers that first click.
    func updateKeyBehavior(for state: GeraState) {
        guard let panel else { return }
        if case .awaitingApproval = state {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Moves the panel to the place configured by the user.
    func reposition() {
        guard let panel, let screen = PanelPlacement.screen(containing: NSEvent.mouseLocation) else { return }
        let geometry = ScreenGeometry(screen: screen)
        let origin = PanelPlacement.origin(
            position: settings.panelPosition,
            panelSize: panel.frame.size,
            screen: geometry,
            menuBarIconRect: MenuBarIconLocator.iconRect()
        )
        var frame = panel.frame
        frame.origin = origin
        // Streaming calls `show` on every delta: do not touch the window when
        // the position is already right, otherwise each delta triggers layout.
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
        let position = self.settings.panelPosition.rawValue
        Log.ui.info(
            "hud frame \(NSStringFromRect(frame), privacy: .public) position \(position, privacy: .public)"
        )
    }

    /// Applies a new content height, throttled and only after the layout pass.
    ///
    /// The height arrives from inside the SwiftUI layout pass, so `resizeScheduler`
    /// defers it. The panel frame is then set directly, without the window animator:
    /// animating the window while SwiftUI lays out the growing card adds a second
    /// layout rhythm, and the two owners of the frame used to feed the AppKit
    /// "Update Constraints in Window" loop.
    func requestHeight(_ height: CGFloat) {
        guard height > 1, panel != nil else { return }
        let target = min(max(height, HUDTheme.minHeight), maxHeight())
        resizeScheduler.submit(target) { [weak self] height in
            self?.applyThrottled(height)
        }
    }

    /// Keeps one resize per `resizeInterval`, so streaming text does not move the
    /// window on every frame.
    private func applyThrottled(_ height: CGFloat) {
        pendingHeight = height
        guard Date().timeIntervalSince(lastResizeAt) >= Self.resizeInterval else {
            scheduleFlush()
            return
        }
        applyHeight(height)
    }

    /// Highest allowed panel height for the current screen.
    func maxHeight() -> CGFloat {
        guard let screen = PanelPlacement.screen(containing: NSEvent.mouseLocation) else {
            return CGFloat.infinity
        }
        return screen.frame.height * settings.maxPanelHeightFraction
    }

    private func scheduleFlush() {
        guard resizeTask == nil else { return }
        resizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, !Task.isCancelled else { return }
            self.resizeTask = nil
            guard let pending = self.pendingHeight else { return }
            guard Date().timeIntervalSince(self.lastResizeAt) >= Self.resizeInterval else {
                self.scheduleFlush()
                return
            }
            self.applyHeight(pending)
        }
    }

    private func applyHeight(_ height: CGFloat) {
        guard let panel else { return }
        pendingHeight = nil
        lastResizeAt = Date()
        let current = panel.frame
        let difference = abs(current.height - height)
        guard difference > 0.5 else { return }
        // The top edge stays in place, so the panel grows downwards.
        let target = CGRect(
            x: current.origin.x,
            y: current.maxY - height,
            width: current.width,
            height: height
        )
        panel.setFrame(target, display: true)
    }

    private func observeScreenChanges() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reposition() }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reposition() }
            }
        )
    }
}
