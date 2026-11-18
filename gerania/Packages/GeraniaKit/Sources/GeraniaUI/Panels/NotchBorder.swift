import SwiftUI

/// Outline of the notch card without the top edge.
///
/// The panel hangs from the top of the screen, so a stroke along the top edge would
/// be clipped away. The thinking highlight therefore runs down the sides and around
/// the bottom, where it is actually visible.
public struct NotchBorder: Shape {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    /// Keeps the whole stroke inside the card instead of half-clipping it.
    public var inset: CGFloat

    public init(
        topCornerRadius: CGFloat = 8,
        bottomCornerRadius: CGFloat = 18,
        inset: CGFloat = 1
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.inset = inset
    }

    public func path(in rect: CGRect) -> Path {
        let frame = rect.insetBy(dx: inset, dy: inset)
        let top = topCornerRadius
        let bottom = bottomCornerRadius
        var path = Path()

        // Start under the left ear and travel down the left side.
        path.move(to: CGPoint(x: frame.minX + top, y: frame.minY + top))
        path.addLine(to: CGPoint(x: frame.minX + top, y: frame.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: frame.minX + top + bottom, y: frame.maxY),
            control: CGPoint(x: frame.minX + top, y: frame.maxY)
        )
        path.addLine(to: CGPoint(x: frame.maxX - top - bottom, y: frame.maxY))
        path.addQuadCurve(
            to: CGPoint(x: frame.maxX - top, y: frame.maxY - bottom),
            control: CGPoint(x: frame.maxX - top, y: frame.maxY)
        )
        path.addLine(to: CGPoint(x: frame.maxX - top, y: frame.minY + top))
        return path
    }
}
