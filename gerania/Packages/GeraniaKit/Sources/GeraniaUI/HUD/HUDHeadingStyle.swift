import SwiftUI
import Textual

/// Compact headings for the HUD: the answer is read in a small panel, so the
/// document hierarchy has to stay tight.
public struct HUDHeadingStyle: StructuredText.HeadingStyle {
    private static let fontScales: [CGFloat] = [1.35, 1.22, 1.12, 1.06, 1.02, 1]

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let level = min(max(configuration.headingLevel, 1), 6)
        configuration.label
            .textual.fontScale(Self.fontScales[level - 1])
            .textual.blockSpacing(.fontScaled(top: 0.9, bottom: 0.35))
            .fontWeight(.semibold)
    }
}
