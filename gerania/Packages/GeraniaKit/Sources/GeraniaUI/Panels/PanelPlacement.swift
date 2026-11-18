import AppKit
import CoreGraphics
import Foundation
import GeraniaCore

/// Pure geometry of the panel placement.
///
/// Every rule lives here so it can be unit-tested on fake screens; the controllers
/// only translate the result into an `NSWindow` frame.
public enum PanelPlacement {
    /// Gap between the panel and the screen edges.
    public static let cornerMargin: CGFloat = 12
    /// Gap between the panel and the menu bar when the display has no notch.
    public static let notchGap: CGFloat = 8
    /// Gap between the panel and the menu bar icon.
    public static let menuBarIconGap: CGFloat = 6

    /// Top-left corner of the panel for the given position.
    public static func origin(
        position: PanelPosition,
        panelSize: CGSize,
        screen: ScreenGeometry,
        menuBarIconRect: CGRect? = nil
    ) -> CGPoint {
        switch position {
        case .notch:
            return notchOrigin(panelSize: panelSize, screen: screen)
        case .topRight:
            return topRightOrigin(panelSize: panelSize, screen: screen)
        case .belowMenuBarIcon:
            guard let menuBarIconRect else {
                return topRightOrigin(panelSize: panelSize, screen: screen)
            }
            return menuBarIconOrigin(panelSize: panelSize, screen: screen, iconRect: menuBarIconRect)
        }
    }

    /// Origin of the bottom prompt: horizontally centred above the Dock.
    public static func bottomCenterOrigin(
        panelSize: CGSize,
        screen: ScreenGeometry,
        margin: CGFloat
    ) -> CGPoint {
        let visible = screen.visibleFrame
        let x = clampedX(visible.midX - panelSize.width / 2, width: panelSize.width, screen: visible)
        return CGPoint(x: x, y: visible.minY + margin)
    }

    /// Clamps a horizontal origin so the panel stays inside the visible frame.
    public static func clampedX(_ x: CGFloat, width: CGFloat, screen: CGRect) -> CGFloat {
        let maximum = max(screen.minX, screen.maxX - width)
        return min(max(x, screen.minX), maximum)
    }

    /// Screen that contains the given global point.
    public static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private static func notchOrigin(panelSize: CGSize, screen: ScreenGeometry) -> CGPoint {
        // On a notch display the panel hangs directly from the top edge, so its black
        // silhouette merges with the camera housing. External displays keep a small gap
        // under the menu bar.
        let y: CGFloat = if screen.hasNotch {
            screen.frame.maxY - panelSize.height
        } else {
            screen.visibleFrame.maxY - notchGap - panelSize.height
        }
        let x = screen.notchCenterX - panelSize.width / 2
        return CGPoint(x: clampX(x, width: panelSize.width, screen: screen), y: y)
    }

    private static func topRightOrigin(panelSize: CGSize, screen: ScreenGeometry) -> CGPoint {
        let x = screen.visibleFrame.maxX - panelSize.width - cornerMargin
        let y = screen.visibleFrame.maxY - panelSize.height - cornerMargin
        return CGPoint(x: x, y: y)
    }

    private static func menuBarIconOrigin(
        panelSize: CGSize,
        screen: ScreenGeometry,
        iconRect: CGRect
    ) -> CGPoint {
        let x = iconRect.midX - panelSize.width / 2
        let y = iconRect.minY - menuBarIconGap - panelSize.height
        return CGPoint(x: clampX(x, width: panelSize.width, screen: screen), y: y)
    }

    private static func clampX(_ x: CGFloat, width: CGFloat, screen: ScreenGeometry) -> CGFloat {
        clampedX(x, width: width, screen: screen.visibleFrame)
    }
}
