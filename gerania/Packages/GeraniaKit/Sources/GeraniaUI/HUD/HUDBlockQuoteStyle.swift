import SwiftUI
import Textual

/// Block quote with a thin rule instead of a filled box.
public struct HUDBlockQuoteStyle: StructuredText.BlockQuoteStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 2)
            configuration.label
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textual.blockSpacing(.fontScaled(top: 0.6, bottom: 0.6))
    }
}
