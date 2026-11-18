import GeraniaCore
import SwiftUI

/// One entry opened for editing.
struct MemoryDraft: Identifiable {
    let id = UUID()
    let kind: MemoryKind
    let index: Int
    let text: String
    let limit: Int
}

/// Sheet with a single memory entry.
///
/// Saving goes through the store: the fingerprint is checked there, so a file
/// changed by Hermes in the meantime leaves the sheet open with an explanation
/// instead of overwriting the other change.
struct MemoryEditor: View {
    let draft: MemoryDraft
    let onSave: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var errorText: String?
    @State private var isSaving = false

    init(draft: MemoryDraft, onSave: @escaping (String) async -> String?) {
        self.draft = draft
        self.onSave = onSave
        _text = State(initialValue: draft.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Изменить запись")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(draft.kind.title) · \(draft.kind.fileName)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $text)
                .font(.system(size: 12))
                .frame(minHeight: 150)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
            HStack {
                Text("\(text.unicodeScalars.count) символов · лимит файла \(draft.limit)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(text.unicodeScalars.count > draft.limit ? .red : .secondary)
                Spacer()
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Отмена") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 430)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorText = nil
        Task { @MainActor in
            errorText = await onSave(text)
            isSaving = false
            if errorText == nil {
                dismiss()
            }
        }
    }
}
