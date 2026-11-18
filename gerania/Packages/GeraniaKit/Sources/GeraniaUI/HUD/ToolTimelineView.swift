import AppKit
import GeraniaCore
import SwiftUI

/// Full timeline of the tool calls in the answer window.
///
/// The compact HUD shows only the last three actions; here every call is listed
/// with its human phrase, the short result and, if the tool made one, the
/// screenshot.
struct ToolTimelineView: View {
    let tools: [ToolChip]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Инструменты")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(HUDTheme.textSecondary)
            ForEach(tools) { tool in
                row(tool)
            }
        }
    }

    private func row(_ tool: ToolChip) -> some View {
        let activity = ToolActivityFormatter.activity(for: tool)
        return HStack(alignment: .top, spacing: 7) {
            Image(systemName: activity.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tool.isError ? HUDTheme.errorTint : HUDTheme.textSecondary)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(activity.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tool.isError ? HUDTheme.errorTint : HUDTheme.textPrimary)
                    if let detail = activity.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(HUDTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if let summary = tool.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let path = tool.imagePath {
                    ToolScreenshot(path: path)
                }
            }
            Spacer(minLength: 0)
            status(tool)
                .frame(width: 12, height: 12)
        }
    }

    @ViewBuilder
    private func status(_ tool: ToolChip) -> some View {
        if tool.isFinished {
            Image(systemName: tool.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(tool.isError ? HUDTheme.errorTint : Color.green.opacity(0.8))
        } else {
            ToolSpinner()
        }
    }
}

/// A screenshot the tool produced; click opens the full image in Preview.
private struct ToolScreenshot: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280, maxHeight: 180, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
                    .onTapGesture {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .help("Открыть скриншот в Preview")
            }
        }
        .task(id: path) {
            let expanded = NSString(string: path).expandingTildeInPath
            image = NSImage(contentsOfFile: expanded)
        }
    }
}
