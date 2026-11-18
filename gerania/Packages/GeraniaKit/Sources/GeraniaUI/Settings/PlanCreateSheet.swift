import HermesKit
import SwiftUI

/// Creates one Hermes cron job from a template or from scratch.
///
/// The sheet only builds the arguments; `PlansModel` runs `hermes cron create`
/// and reloads the list, so the scheduler validates the schedule and the
/// timezone exactly as it would from the terminal.
struct PlanCreateSheet: View {
    let model: PlansModel
    @Environment(\.dismiss) private var dismiss

    @State private var templateID = PlanTemplates.all.first?.id ?? ""
    @State private var name = PlanTemplates.all.first?.title ?? ""
    @State private var schedule = PlanTemplates.all.first?.schedule ?? ""
    @State private var prompt = PlanTemplates.all.first?.prompt ?? ""
    @State private var timezone = TimeZone.current.identifier
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Новый план")
                    .font(.system(size: 14, weight: .semibold))
                Text("Шаблон заполнит поля — их можно изменить. Hermes создаст задачу с доставкой в приложение.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Шаблон", selection: $templateID) {
                ForEach(PlanTemplates.all) { template in
                    Text(template.title).tag(template.id)
                }
            }
            .onChange(of: templateID) { _, id in
                applyTemplate(id)
            }
            field("Название", text: $name, prompt: "Утренний брифинг")
            field("Расписание", text: $schedule, prompt: "0 8 * * * · every 2h · in 30m")
            field("Часовой пояс", text: $timezone, prompt: TimeZone.current.identifier)
            VStack(alignment: .leading, spacing: 3) {
                Text("Что делать")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $prompt)
                    .font(.system(size: 11.5))
                    .frame(height: 92)
                    .padding(4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                    }
            }
            HStack {
                Text("Расписание: интервал, `in 2h` или cron-выражение.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Создать") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!request.isValid || isSaving)
            }
        }
        .padding(18)
        .frame(width: 540)
    }

    private var request: CronJobRequest {
        CronJobRequest(name: name, schedule: schedule, prompt: prompt, timezone: timezone)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
        }
    }

    private func applyTemplate(_ id: String) {
        guard let template = PlanTemplates.all.first(where: { $0.id == id }) else { return }
        name = template.title
        schedule = template.schedule
        prompt = template.prompt
    }

    private func save() {
        guard request.isValid, !isSaving else { return }
        isSaving = true
        errorText = nil
        Task { @MainActor in
            let created = await model.create(request)
            isSaving = false
            if created {
                dismiss()
            } else {
                errorText = model.errorMessage ?? "Не удалось создать план."
            }
        }
    }
}
