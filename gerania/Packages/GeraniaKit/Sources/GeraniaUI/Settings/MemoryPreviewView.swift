import AppKit
import GeraniaCore
import SwiftUI

/// Preview of the memory blocks Hermes injects into a new session.
///
/// The text is produced by `MemoryBlockFormatter`, so it is the same header,
/// usage line and `§`-joined body the model sees — not a hand-made summary.
struct MemoryPreviewView: View {
    let model: MemoryModel
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(MemoryKind.allCases) { kind in
                        if let document = model.document(for: kind) {
                            block(document)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Что Геря узнает в новой сессии")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Оба файла в том виде, в каком Hermes добавляет их в системный промпт.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func block(_ document: MemoryDocument) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(document.kind.fileName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(document.characters) / \(document.limit)")
                    .font(.system(size: 10, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(document.isOverLimit ? Color.orange : Color.secondary)
            }
            Text(MemoryBlockFormatter.preview(for: document))
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}
