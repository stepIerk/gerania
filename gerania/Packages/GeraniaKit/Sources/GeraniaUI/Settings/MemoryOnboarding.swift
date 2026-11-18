import GeraniaCore
import SwiftUI

/// Optional acquaintance form: five questions, one `USER.md` update.
///
/// It is a form rather than a voice dialog on purpose: the answers become
/// deterministic entries in the profile, and a free model cannot lose a field
/// between turns. Every question may be skipped; the file is written once.
struct MemoryOnboarding: View {
    let model: MemoryModel
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = MemoryProfileDraft()
    @State private var errorText: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Давайте познакомимся")
                    .font(.system(size: 14, weight: .semibold))
                Text("Пять коротких вопросов — Гера заполнит профиль. Можно ответить на часть и вернуться позже.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            field("Как обращаться", text: $draft.name, prompt: "Степан, на «ты»")
            field("Город", text: $draft.city, prompt: "Москва — часовой пояс подставим сами")
            field(
                "Учёба или работа",
                text: $draft.study,
                prompt: "МГУ, 3 курс; пары по средам в 10:00",
                lines: 1 ... 2
            )
            field(
                "Стек",
                text: $draft.stack,
                prompt: "Swift, Python, Xcode; учу алгоритмы",
                lines: 1 ... 2
            )
            field("Стиль ответов", text: $draft.style, prompt: "Коротко, с примерами кода")
            field(
                "Ещё",
                text: $draft.notes,
                prompt: "Не будить до 10 утра; люблю тёмную тему",
                lines: 1 ... 3
            )
            HStack(spacing: 6) {
                Text(entriesPreview)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Пропустить") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Записать в память") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || entries.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 480)
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        lines: ClosedRange<Int> = 1 ... 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
                .lineLimit(lines)
        }
    }

    private var entries: [String] {
        draft.entries()
    }

    private var entriesPreview: String {
        switch entries.count {
        case 0: "Пока пусто: заполните хотя бы одно поле."
        case 1: "Будет добавлена 1 запись в USER.md."
        default: "Будет добавлено \(entries.count) записи в USER.md."
        }
    }

    private func save() {
        let values = entries
        guard !values.isEmpty, !isSaving else { return }
        isSaving = true
        errorText = nil
        Task { @MainActor in
            let saved = await model.addFacts(values, to: .user)
            isSaving = false
            if saved {
                onFinished()
                dismiss()
            } else {
                errorText = model.errorMessage ?? "Не удалось записать профиль."
            }
        }
    }
}
