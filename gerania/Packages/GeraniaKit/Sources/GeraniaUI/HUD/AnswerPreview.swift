import SwiftUI

/// Compact preview of the answer under the notch.
///
/// The preview shows at most 150 pt of the markdown and follows the stream. The full text
/// is always one click away: the expand action opens the large answer window.
public struct AnswerPreview: View {
    private let model: HUDViewModel
    private let showsCursor: Bool

    @State private var contentHeight: CGFloat = 0

    private static let maximumHeight: CGFloat = 150
    private static let cursorID = "gerania.hud.cursor"

    public init(model: HUDViewModel, showsCursor: Bool) {
        self.model = model
        self.showsCursor = showsCursor
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(model.blocks.enumerated()), id: \.offset) { _, block in
                        MarkdownStreamView(markdown: block)
                    }
                    if !model.tail.isEmpty {
                        MarkdownStreamView(markdown: model.tail)
                    }
                    if showsCursor {
                        StreamingCursor()
                            .id(Self.cursorID)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }
            }
            .frame(height: min(max(contentHeight, 0), Self.maximumHeight))
            .scrollIndicators(.hidden)
            .onChange(of: model.streamedText) { _, _ in
                guard showsCursor else { return }
                proxy.scrollTo(Self.cursorID, anchor: .bottom)
            }
        }
        .overlay(alignment: .bottom) {
            if contentHeight > Self.maximumHeight {
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 20)
            }
        }
    }
}
