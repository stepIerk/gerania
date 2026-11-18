import SwiftUI
import Textual

/// Table cell with compact padding.
public struct HUDTableCellStyle: StructuredText.TableCellStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.fontScale(0.95)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
