import SwiftUI
import Textual

/// Table with a thin grid instead of the heavy default frame.
public struct HUDTableStyle: StructuredText.TableStyle {
    private static let lineWidth: CGFloat = 0.5

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.tableCellSpacing(horizontal: Self.lineWidth, vertical: Self.lineWidth)
            .textual.blockSpacing(.fontScaled(top: 0.9, bottom: 0.9))
            .textual.tableOverlay { layout in
                Canvas { context, _ in
                    for divider in layout.dividers() {
                        context.fill(
                            Path(divider),
                            with: .style(Color.secondary.opacity(0.25))
                        )
                    }
                }
            }
            .padding(Self.lineWidth)
    }
}
