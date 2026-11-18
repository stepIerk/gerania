import AppKit
import Foundation

/// Best-effort lookup of the menu-bar button rectangle in global screen coordinates.
///
/// The SwiftUI `MenuBarExtra` does not expose its status item, so the app windows are
/// scanned instead. When nothing is found the caller falls back to the top-right corner.
@MainActor
public enum MenuBarIconLocator {
    /// Maximum width of a plausible status item button.
    private static let maxIconWidth: CGFloat = 400

    /// Rectangle of the menu bar icon in screen coordinates, if it can be found.
    public static func iconRect() -> CGRect? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let thickness = NSStatusBar.system.thickness
        for window in NSApp.windows where isStatusItem(window) {
            let frame = window.frame
            guard frame.width > 0, frame.width <= maxIconWidth, screens.contains(where: { isInMenuBar(
                frame,
                screen: $0,
                thickness: thickness
            ) }) else {
                continue
            }
            return frame
        }
        return nil
    }

    private static func isStatusItem(_ window: NSWindow) -> Bool {
        guard window.isVisible else { return false }
        return window.styleMask.contains(.borderless) || window.className.contains("StatusBar")
    }

    private static func isInMenuBar(_ frame: CGRect, screen: NSScreen, thickness: CGFloat) -> Bool {
        let top = screen.frame.maxY
        return frame.maxY >= top - 2 && frame.minY >= top - thickness - 6
    }
}
