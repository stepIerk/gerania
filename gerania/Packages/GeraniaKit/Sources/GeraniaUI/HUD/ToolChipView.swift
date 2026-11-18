import GeraniaCore
import SwiftUI

/// One tool call shown while the assistant is thinking.
///
/// The technical name (`browser_exec`, `computer_use`) and the raw arguments
/// become a short human phrase: «Открываю сайт · example.com».
public struct ToolChipView: View {
    private let chip: ToolChip
    private let activity: ToolActivity

    public init(chip: ToolChip) {
        self.chip = chip
        activity = ToolActivityFormatter.activity(for: chip)
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: activity.symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(activity.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let detail = activity.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            statusIcon
                .frame(width: 11, height: 11)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(HUDTheme.controlFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .transition(.push(from: .leading).combined(with: .opacity))
    }

    @ViewBuilder
    private var statusIcon: some View {
        if chip.isFinished {
            Image(systemName: chip.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(chip.isError ? HUDTheme.errorTint : Color.green.opacity(0.8))
        } else {
            ToolSpinner()
        }
    }
}

/// How many earlier tool calls are hidden behind the last three.
struct ToolOverflowChip: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(HUDTheme.controlFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .help("Ещё действий: \(count) — полный список в окне ответа")
            .transition(.push(from: .leading).combined(with: .opacity))
    }
}

/// A small rotating arc: the marker of a tool that is still running.
struct ToolSpinner: View {
    @State private var angle = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(angle))
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(120))
                    angle = (angle + 40).truncatingRemainder(dividingBy: 360)
                }
            }
    }
}
