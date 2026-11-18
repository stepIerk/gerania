import SwiftUI
import Textual

/// Code block with a quiet background and a copy button.
public struct HUDCodeBlockStyle: StructuredText.CodeBlockStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            configuration.label
                .textual.fontScale(0.95)
                .textual.lineSpacing(.fontScaled(0.25))
                .fixedSize(horizontal: false, vertical: true)
                .monospaced()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            Button {
                configuration.codeBlock.copyToPasteboard()
            } label: {
                Label("Копировать", systemImage: "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
        }
        .textual.blockSpacing(.fontScaled(top: 0.8, bottom: 0))
    }
}
