import AppKit
import GeraniaCore
import HermesKit
import SwiftUI
import UniformTypeIdentifiers
import VoiceKit

/// «Диагностика»: what works right now, where the logs are and a report to send.
struct DiagnosticsTab: View {
    let settings: GeraSettings

    @State private var sections: [DiagnosticsReport.Section] = []
    @State private var exportMessage: String?
    @State private var isExporting = false

    var body: some View {
        Form {
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.0) {
                            Text(row.1)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            Section("Логи") {
                Text(
                    "Журнал Геры — в приложении «Консоль»: поиск по subsystem \(DiagnosticsCollector.subsystem). "
                        + "Журналы Hermes лежат в \(DiagnosticsCollector.hermesLogsDirectory.path)."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                HStack {
                    Button("Открыть логи Hermes") {
                        NSWorkspace.shared.open(DiagnosticsCollector.hermesLogsDirectory)
                    }
                    Button("Открыть «Консоль»") {
                        openConsole()
                    }
                }
            }
            Section("Отчёт") {
                Text(
                    "Отчёт — текстовый файл с версиями, состоянием и журналом Геры за последний час. "
                        + "Ключи и токены в нём заменяются на «[скрыто]». Его можно отправить разработчику."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                HStack {
                    Button("Экспортировать отчёт…") {
                        Task { await export() }
                    }
                    .disabled(isExporting)
                    Button("Обновить") {
                        refresh()
                    }
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                if let exportMessage {
                    Text(exportMessage)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refresh() }
    }

    private func refresh() {
        sections = DiagnosticsCollector.facts(settings: settings)
    }

    private func openConsole() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        let report = await DiagnosticsCollector.build(settings: settings)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = report.fileName
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else {
            exportMessage = nil
            return
        }
        do {
            try report.text.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Сохранено: \(url.path)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportMessage = "Не удалось сохранить отчёт: \(error.localizedDescription)"
        }
    }
}
