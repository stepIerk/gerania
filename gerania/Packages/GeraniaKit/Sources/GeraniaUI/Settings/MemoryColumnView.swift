import GeraniaCore
import SwiftUI

/// One column of the «Память» tab: a file, its entries and the add field.
struct MemoryColumnView: View {
    let kind: MemoryKind
    let document: MemoryDocument?
    let isBusy: Bool
    let onAdd: (String) async -> Bool
    let onEdit: (Int) -> Void
    let onRemove: (Int) -> Void
    let onClear: () -> Void

    @State private var newFact = ""
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if let document {
                counter(document)
                if document.entries.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(document.entries.enumerated()), id: \.offset) { index, entry in
                        entryCard(entry, index: index)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            }
            addField
            HStack {
                Spacer()
                Button("Забыть всё") {
                    onClear()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10.5))
                .foregroundStyle(.red)
                .disabled(isBusy || document?.isEmpty != false)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(kind.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let document {
                Text(document.countText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func counter(_ document: MemoryDocument) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text("\(document.characters) / \(document.limit)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(counterColor(document))
                Text("символов")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                if document.isOverLimit {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .help("Файл больше лимита Hermes: новые записи не поместятся, пока вы что-нибудь не забудете.")
                }
            }
            ProgressView(
                value: Double(min(document.characters, document.limit)),
                total: Double(max(1, document.limit))
            )
            .progressViewStyle(.linear)
            .tint(counterColor(document))
        }
    }

    private var emptyState: some View {
        Text("Пока пусто. Добавьте первый факт — он попадёт в профиль следующей сессии.")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
    }

    private func entryCard(_ entry: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry)
                .font(.system(size: 11.5))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Изменить") {
                    onEdit(index)
                }
                .help("Открыть запись в редакторе")
                Button("Забыть") {
                    onRemove(index)
                }
                .foregroundStyle(.red)
                .help("Удалить только эту запись")
                Spacer(minLength: 0)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 10.5))
            .disabled(isBusy)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    private var addField: some View {
        HStack(spacing: 6) {
            TextField("Добавить факт…", text: $newFact, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .lineLimit(1 ... 3)
                .onSubmit(add)
            Button {
                add()
            } label: {
                if isAdding {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                }
            }
            .buttonStyle(.borderless)
            .disabled(!canAdd)
            .help("Добавить запись в \(kind.fileName)")
        }
    }

    private var canAdd: Bool {
        !isBusy && !isAdding && !newFact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        let text = newFact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAdd, !text.isEmpty else { return }
        isAdding = true
        Task { @MainActor in
            let added = await onAdd(text)
            if added {
                newFact = ""
            }
            isAdding = false
        }
    }

    private func counterColor(_ document: MemoryDocument) -> Color {
        if document.isOverLimit {
            return .red
        }
        return document.remaining < 150 ? .orange : .secondary
    }
}
