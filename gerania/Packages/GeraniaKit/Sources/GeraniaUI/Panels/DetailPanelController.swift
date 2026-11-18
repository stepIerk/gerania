import AppKit
import GeraniaCore
import SwiftUI

/// Large black window with the full answer, placed beside the notch HUD.
///
/// It opens without activating the app. Clicking it makes it the key window so the
/// user can scroll, select text and use the footer, but the menu bar and Dock still
/// belong to the application in front.
@MainActor
public final class DetailPanelController {
    /// Width the user can choose in the settings.
    public static let maximumWidth: CGFloat = 720
    /// Maximum height of the reading window.
    public static let maximumHeight: CGFloat = 720
    /// Gap to the top and bottom screen edges.
    public static let verticalMargin: CGFloat = 24

    private let model: HUDViewModel
    private let settings: GeraSettings
    private var panel: FloatingPanel?
    private var isVisible = false

    public init(model: HUDViewModel, settings: GeraSettings) {
        self.model = model
        self.settings = settings
    }

    public var isPanelVisible: Bool {
        isVisible
    }

    public func show() {
        ensurePanel()
        guard let panel else { return }
        position()
        guard !isVisible else { return }
        isVisible = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        Log.ui.info("answer detail shown")
    }

    public func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel?.orderOut(nil)
                self?.panel?.alphaValue = 1
            }
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 480),
            acceptsKey: true
        )
        panel.host(
            PanelCard(cornerRadius: 16, padding: 0) {
                AnswerDetailView(model: model) { [weak self] in
                    self?.hide()
                }
            }
        )
        panel.onEscape = { [weak self] in
            self?.hide()
        }
        self.panel = panel
    }

    private func position() {
        guard let panel, let screen = PanelPlacement.screen(containing: NSEvent.mouseLocation) else {
            return
        }
        let visible = screen.visibleFrame
        let panelWidth = min(width, visible.width - margin * 2)
        let height = min(Self.maximumHeight, visible.height - Self.verticalMargin * 2)
        // The reading window hugs the right edge by default; the margin is a setting.
        let x = visible.maxX - panelWidth - margin
        let y = visible.midY - height / 2
        panel.setFrame(
            CGRect(x: x, y: y, width: panelWidth, height: height),
            display: true
        )
    }

    private var width: CGFloat {
        min(max(CGFloat(settings.detailPanelWidth), 400), Self.maximumWidth)
    }

    private var margin: CGFloat {
        max(0, CGFloat(settings.detailPanelMargin))
    }
}
