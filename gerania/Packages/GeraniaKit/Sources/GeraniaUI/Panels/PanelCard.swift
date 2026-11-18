import SwiftUI

/// Black rounded surface used by the mini window and the expanded answer.
///
/// It is intentionally opaque: the panels sit above other applications and must stay
/// readable without picking up the colour of whatever is behind them.
public struct PanelCard<Content: View>: View {
    private let content: Content
    private let cornerRadius: CGFloat
    private let padding: CGFloat

    public init(
        cornerRadius: CGFloat = HUDTheme.panelRadius,
        padding: CGFloat = HUDTheme.padding,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    public var body: some View {
        content
            .padding(padding)
            .background {
                shape.fill(Color.black)
            }
            .overlay {
                shape.strokeBorder(HUDTheme.hairline, lineWidth: 0.5)
            }
            .clipShape(shape)
            .environment(\.colorScheme, .dark)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}
