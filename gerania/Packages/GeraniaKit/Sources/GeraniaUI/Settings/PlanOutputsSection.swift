import AppKit
import HermesKit
import SwiftUI

/// Result files Hermes wrote after running a plan.
struct PlanOutputsSection: View {
    let outputs: [CronOutput]
    let directory: URL

    var body: some View {
        Section("Последние результаты") {
            HStack {
                Text("Файлы из `~/.hermes/cron/output`")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Показать в Finder") {
                    NSWorkspace.shared.open(directory.appendingPathComponent("output", isDirectory: true))
                }
            }
            if outputs.isEmpty {
                Text("Результатов пока нет: они появятся после первого запуска плана.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(outputs) { output in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(output.fileName)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(output.modifiedAt, format: .dateTime.day().month().hour().minute())
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        Button("Открыть") {
                            NSWorkspace.shared.open(output.url)
                        }
                    }
                }
            }
        }
    }
}
