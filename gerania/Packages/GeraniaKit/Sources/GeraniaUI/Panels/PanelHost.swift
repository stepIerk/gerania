import AppKit
import SwiftUI

/// Transparent hosting view used as the content of a `FloatingPanel`.
///
/// The SwiftUI root paints its own background, so the hosting view and the window
/// behind it must stay fully transparent.
@MainActor
public final class PanelHost<Content: View>: NSHostingView<Content> {
    public required init(rootView: Content) {
        super.init(rootView: rootView)
        // The controller owns the window size: the hosting view must not resize it.
        sizingOptions = []
        makeTransparent()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        nil
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        makeTransparent()
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }

    /// The HUD is a passive panel: its buttons must react to the first click even
    /// though the window never becomes key.
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func makeTransparent() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
