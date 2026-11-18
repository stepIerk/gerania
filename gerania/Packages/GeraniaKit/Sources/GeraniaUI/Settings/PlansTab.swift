import GeraniaCore
import HermesKit
import SwiftUI

/// Settings tab: the scheduled jobs of Hermes.
///
/// The list is read from `~/.hermes/cron/jobs.json`; pause, resume, run and
/// remove go through `hermes cron ...`. Results are the markdown files Hermes
/// drops under `cron/output/`. Creating a plan is an explicit form, and deleting
/// one asks for confirmation — the two actions that are not trivially undoable.
public struct PlansTab: View {
    @State private var model: PlansModel
    @State private var showingCreate = false
    @State private var pendingRemoval: CronJob?

    @MainActor
    public init(settings: GeraSettings) {
        _model = State(initialValue: PlansModel(settings: settings))
    }

    @MainActor
    public init(model: PlansModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Form {
            Section("Планы Геры") {
                header
                if let status = model.statusMessage {
                    message(status, symbol: "checkmark.circle.fill", color: .green)
                }
                if let error = model.errorMessage {
                    message(error, symbol: "exclamationmark.triangle.fill", color: .orange)
                }
                if model.jobs.isEmpty, !model.isLoading {
                    Text("Пока нет планов. Нажмите «Создать» или скажите Гере: «напоминай каждый день в 8 утра».")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.jobs) { job in
                        PlanJobRow(
                            job: job,
                            isBusy: model.isBusy,
                            onPause: { Task { await model.pause(job) } },
                            onResume: { Task { await model.resume(job) } },
                            onRun: { Task { await model.runNow(job) } },
                            onDelete: { pendingRemoval = job }
                        )
                    }
                }
            }
            PlanOutputsSection(outputs: model.outputs, directory: model.directory)
            Section {
                Text("Планы живут в Hermes: изменения из чата появляются здесь после «Обновить».")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text("Файлы: \(abbreviatedDirectory)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .task { await model.load() }
        .sheet(isPresented: $showingCreate) {
            PlanCreateSheet(model: model)
        }
        .confirmationDialog(
            "Удалить план «\(pendingRemoval?.name ?? "")»?",
            isPresented: removalPresented,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                guard let job = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await model.remove(job) }
            }
            Button("Отмена", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text("Задача исчезнет из расписания Hermes. Отменить это будет нельзя.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Запланированные задачи")
                    .font(.system(size: 12, weight: .medium))
                Text(summary)
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
                showingCreate = true
            } label: {
                Label("Создать", systemImage: "plus")
            }
            .disabled(model.isBusy)
        }
    }

    private var summary: String {
        let active = model.jobs.filter { !$0.isPaused && !$0.isCompleted }.count
        let paused = model.jobs.filter(\.isPaused).count
        switch model.jobs.count {
        case 0: return "Ни одной задачи"
        case 1: return paused == 1 ? "1 задача на паузе" : "1 активная задача"
        default:
            return paused > 0
                ? "\(active) активных, \(paused) на паузе"
                : "\(active) активных задач"
        }
    }

    private func message(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                model.dismissMessages()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Скрыть сообщение")
        }
    }

    private var abbreviatedDirectory: String {
        (model.directory.path as NSString).abbreviatingWithTildeInPath
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { presented in
                if !presented {
                    pendingRemoval = nil
                }
            }
        )
    }
}
