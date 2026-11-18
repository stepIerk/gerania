import AppKit
import CoreGraphics
import Foundation

/// Screen metrics required to place a panel.
///
/// A plain value type so the placement math can be tested without a real display.
public struct ScreenGeometry: Equatable, Sendable {
    /// Full screen frame in global screen coordinates (origin bottom-left).
    public var frame: CGRect
    /// Screen frame without the menu bar and the Dock.
    public var visibleFrame: CGRect
    /// Top safe-area inset (camera housing / notch).
    public var safeAreaTop: CGFloat
    /// Menu bar area left of the notch. Empty on displays without a notch.
    public var auxiliaryTopLeftArea: CGRect
    /// Menu bar area right of the notch. Empty on displays without a notch.
    public var auxiliaryTopRightArea: CGRect

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat = 0,
        auxiliaryTopLeftArea: CGRect = .zero,
        auxiliaryTopRightArea: CGRect = .zero
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
    }

    public init(screen: NSScreen) {
        self.init(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea ?? .zero,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea ?? .zero
        )
    }

    /// `true` when the display has a camera housing between the two auxiliary areas.
    public var hasNotch: Bool {
        !auxiliaryTopLeftArea.isEmpty
            && !auxiliaryTopRightArea.isEmpty
            && auxiliaryTopLeftArea.maxX < auxiliaryTopRightArea.minX
    }

    /// Height of the menu bar strip, including the notch area.
    public var menuBarHeight: CGFloat {
        max(0, frame.maxY - visibleFrame.maxY)
    }

    /// Horizontal centre of the notch, or the centre of the visible area.
    public var notchCenterX: CGFloat {
        guard hasNotch else { return visibleFrame.midX }
        return (auxiliaryTopLeftArea.maxX + auxiliaryTopRightArea.minX) / 2
    }
}
