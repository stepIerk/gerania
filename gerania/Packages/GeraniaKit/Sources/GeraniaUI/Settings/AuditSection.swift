import AppKit
import GeraniaCore
import SwiftUI

/// Settings section: what did Gerania run on this Mac?
///
/// The journal is an append-only JSONL file; this card shows the newest lines
/// and opens the file in Finder. Arguments are already redacted by `AuditLog`.
public struct AuditSection: View {
    private let log: AuditLog

    @State private var entries: [AuditEntry] = []
    @State private var isLoading = false

    public init(log: AuditLog) {
        self.log = log
    }

    public var body: some View {
        Section("Журнал действий") {
            LabeledContent("Файл", value: "~/Library/Application Support/Gerania/audit.jsonl")
            HStack(spacing: 8) {
                Button("Обновить") {
                    Task { await refresh() }
                }
                .disabled(isLoading)
                Button("Показать в Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([log.url])
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text("\(entries.count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if entries.isEmpty, !isLoading {
                Text("Пока пусто: здесь появятся поиски, браузер, компьютер и подтверждения.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries.suffix(20).reversed()) { entry in
                    row(entry)
                }
            }
            Text("Строки дописываются после каждого действия; пароли и токены в аргументах заменяются на ***.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .task { await refresh() }
    }

    private func row(_ entry: AuditEntry) -> some View {
        let activity = activity(for: entry)
        return HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol(for: entry.ok))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(entry.ok == false ? Color.red : Color.green.opacity(0.85))
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 11.5, weight: .medium))
                if let detail = activity.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let summary = entry.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(entry.date, format: .dateTime.hour().minute().second())
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func activity(for entry: AuditEntry) -> ToolActivity {
        switch entry.tool {
        case "approval":
            ToolActivity(title: "Подтверждение", detail: entry.detail, symbol: "hand.raised")
        case "clarify":
            ToolActivity(title: "Уточнение", detail: entry.detail, symbol: "questionmark.bubble")
        default:
            ToolActivityFormatter.activity(name: entry.tool, detail: entry.detail)
        }
    }

    private func symbol(for ok: Bool?) -> String {
        switch ok {
        case true: "checkmark.circle.fill"
        case false: "xmark.circle.fill"
        case nil: "circle.dotted"
        }
    }

    private func refresh() async {
        isLoading = true
        entries = await log.recent(limit: 100)
        isLoading = false
    }
}
