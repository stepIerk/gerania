import GeraniaCore
import SwiftUI

/// Settings tab: the two curated memory files of Hermes.
///
/// Gerania edits the files directly in the Hermes format. The next session
/// picks the changes up; the current one keeps the profile it started with,
/// so the tab says that instead of pretending the change is immediate.
public struct MemoryTab: View {
    private let model: MemoryModel

    @State private var sheet: MemorySheet?
    @State private var firstClear: MemoryKind?
    @State private var secondClear: MemoryKind?

    public init(model: MemoryModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                topBar
                if let error = model.errorMessage {
                    errorBanner(error)
                }
                if showsProfileCallout {
                    onboardingCallout
                }
                HStack(alignment: .top, spacing: 12) {
                    column(.user)
                    column(.notes)
                }
                footer
            }
            .padding(16)
        }
        .task { await model.load() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case let .edit(draft):
                MemoryEditor(draft: draft) { text in
                    let saved = await model.replaceEntry(text, at: draft.index, in: draft.kind)
                    return saved ? nil : (model.errorMessage ?? "Не удалось сохранить запись.")
                }
            case .onboarding:
                MemoryOnboarding(model: model) {}
            }
        }
        .confirmationDialog(
            "Удалить все записи из «\(firstClear?.title ?? "памяти")»?",
            isPresented: firstClearPresented,
            titleVisibility: .visible
        ) {
            Button("Удалить все записи", role: .destructive) {
                secondClear = firstClear
                firstClear = nil
            }
            Button("Отмена", role: .cancel) {
                firstClear = nil
            }
        } message: {
            Text("Файл \(firstClear?.fileName ?? "") очищается целиком. Спросим ещё раз.")
        }
        .alert("Точно удалить?", isPresented: secondClearPresented) {
            Button("Удалить навсегда", role: .destructive) {
                guard let kind = secondClear else { return }
                secondClear = nil
                Task { await model.clear(kind) }
            }
            Button("Отмена", role: .cancel) {
                secondClear = nil
            }
        } message: {
            Text("Все записи из «\(secondClear?.title ?? "памяти")» исчезнут. Отменить это будет нельзя.")
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Память Геры")
                    .font(.system(size: 14, weight: .semibold))
                Text("Два файла Hermes: профиль человека и заметки агента.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
            Button("Обновить") {
                Task { await model.load() }
            }
            .disabled(model.isLoading || model.isBusy)
            Button {
                sheet = .onboarding
            } label: {
                Label("Знакомство", systemImage: "person.crop.circle")
            }
            .disabled(model.isLoading || model.isBusy)
        }
    }

    private var showsProfileCallout: Bool {
        model.document(for: .user)?.isEmpty == true
    }

    private var onboardingCallout: some View {
        HStack(spacing: 9) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Профиль пока пуст")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("Пять вопросов — и Гера будет знать, как вас зовут, где вы учитесь и что любите.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Заполнить") {
                sheet = .onboarding
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
        }
    }

    private func column(_ kind: MemoryKind) -> some View {
        MemoryColumnView(
            kind: kind,
            document: model.document(for: kind),
            isBusy: model.isBusy || model.isLoading,
            onAdd: { text in
                await model.addFact(text, to: kind)
            },
            onEdit: { index in
                guard let document = model.document(for: kind),
                      document.entries.indices.contains(index) else { return }
                let draft = MemoryDraft(
                    kind: kind,
                    index: index,
                    text: document.entries[index],
                    limit: document.limit
                )
                sheet = .edit(draft)
            },
            onRemove: { index in
                Task { await model.removeEntry(at: index, in: kind) }
            },
            onClear: {
                firstClear = kind
            }
        )
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                model.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Скрыть сообщение")
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Изменения попадут в следующую сессию Hermes: текущая помнит профиль на момент старта.")
            Text("Файлы: \(abbreviatedDirectory)")
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }

    private var abbreviatedDirectory: String {
        (model.directory.path as NSString).abbreviatingWithTildeInPath
    }

    private var firstClearPresented: Binding<Bool> {
        Binding(
            get: { firstClear != nil },
            set: { presented in
                if !presented {
                    firstClear = nil
                }
            }
        )
    }

    private var secondClearPresented: Binding<Bool> {
        Binding(
            get: { secondClear != nil },
            set: { presented in
                if !presented {
                    secondClear = nil
                }
            }
        )
    }
}

/// One sheet at a time: the entry editor or the acquaintance form.
private enum MemorySheet: Identifiable {
    case edit(MemoryDraft)
    case onboarding

    var id: String {
        switch self {
        case let .edit(draft): "edit-\(draft.id.uuidString)"
        case .onboarding: "onboarding"
        }
    }
}
