import AppKit
import SwiftUI

/// Borderless floating panel that lives above every other app.
///
/// The panel never activates the application: `orderFrontRegardless()` keeps the focus
/// in the app the user is working in. `acceptsKey` lets a panel become key when the user
/// clicks it, so buttons, text fields and selection work without switching apps.
public final class FloatingPanel: NSPanel {
    /// Called when the user presses Esc while the panel is the key window.
    public var onEscape: (() -> Void)?

    /// Whether the panel may become the key window.
    public var acceptsKey: Bool

    public init(contentRect: NSRect, acceptsKey: Bool) {
        self.acceptsKey = acceptsKey
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovableByWindowBackground = false
    }

    /// Embeds a SwiftUI view below the window's content view.
    ///
    /// SwiftUI's app lifecycle resizes a window whose `contentView` is an
    /// `NSHostingView` on every layout pass, even when `sizingOptions` is empty:
    /// the gate is `window.contentView === hostingView`. A panel controller owns
    /// the frame, so the hosting view lives one level deeper and follows the
    /// content view with autoresizing instead of Auto Layout. This leaves exactly
    /// one owner of the window size and breaks AppKit's constraint loop.
    @discardableResult
    func host<Content: View>(_ rootView: Content) -> PanelHost<Content> {
        let container: NSView
        if let existing = contentView {
            container = existing
        } else {
            let view = NSView()
            contentView = view
            container = view
        }
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        let host = PanelHost(rootView: rootView)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.frame = container.bounds
        container.addSubview(host)
        return host
    }

    override public var canBecomeKey: Bool {
        acceptsKey
    }

    override public var canBecomeMain: Bool {
        false
    }

    override public func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
