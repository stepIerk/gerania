import SwiftUI
import Textual

/// Renders one markdown block with the HUD typography.
///
/// Every finished block is a separate view, so Textual parses it only once: while the
/// answer streams, only the tail block is parsed again.
public struct MarkdownStreamView: View {
    private let markdown: String

    public init(markdown: String) {
        self.markdown = markdown
    }

    public var body: some View {
        HUDProfiler.measure("hud.markdown") {
            StructuredText(markdown: markdown)
                .font(HUDTheme.bodyFont)
                .textual.headingStyle(HUDHeadingStyle())
                .textual.blockQuoteStyle(HUDBlockQuoteStyle())
                .textual.codeBlockStyle(HUDCodeBlockStyle())
                .textual.tableStyle(HUDTableStyle())
                .textual.tableCellStyle(HUDTableCellStyle())
                .textual.highlighterTheme(.plain)
                .textual.overflowMode(.wrap)
                .textual.blockSpacing(.fontScaled(top: 0.6, bottom: 0.6))
                .textual.lineSpacing(.fontScaled(0.2))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
