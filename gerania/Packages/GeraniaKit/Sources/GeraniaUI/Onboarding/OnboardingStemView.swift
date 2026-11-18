import GeraniaCore
import SwiftUI

/// Colors of the wizard: the black of the loading screen and the notch HUD.
enum OnboardingTheme {
    static let background = Color.black
    static let accent = HUDTheme.accent
    static let ok = Color(red: 0.30, green: 0.82, blue: 0.47)
    static let warning = HUDTheme.computerTint
    static let failure = Color(red: 1.0, green: 0.36, blue: 0.36)
    static let idle = Color.white.opacity(0.22)

    static func color(for status: SetupStatus) -> Color {
        switch status {
        case .ok: ok
        case .warning, .skipped: warning
        case .failed: failure
        case .unknown, .checking: idle
        }
    }

    static func symbol(for status: SetupStatus) -> String {
        switch status {
        case .ok: "checkmark"
        case .warning: "exclamationmark"
        case .skipped: "arrow.uturn.right"
        case .failed: "xmark"
        case .unknown, .checking: ""
        }
    }

    static func spokenStatus(_ status: SetupStatus) -> String {
        switch status {
        case .ok: "готово"
        case .warning: "работает с ограничением"
        case .skipped: "пропущено"
        case .failed: "нужно исправить"
        case .checking: "проверяется"
        case .unknown: "не проверено"
        }
    }
}

/// The left rail: the steps as nodes on a stem that grows as checks turn green.
struct OnboardingStemView: View {
    let progress: SetupProgress
    let onSelect: (SetupStep) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(SetupStep.allCases.enumerated()), id: \.element) { index, step in
                row(step)
                if index < SetupStep.allCases.count - 1 {
                    segment(after: step)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 22)
        .frame(width: 230, alignment: .leading)
    }

    private func row(_ step: SetupStep) -> some View {
        let status = progress.status(of: step)
        let isCurrent = progress.current == step
        return Button {
            onSelect(step)
        } label: {
            HStack(spacing: 12) {
                node(status: status, isCurrent: isCurrent)
                Text(step.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.62))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(step.title): \(OnboardingTheme.spokenStatus(status))")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func node(status: SetupStatus, isCurrent: Bool) -> some View {
        let color = OnboardingTheme.color(for: status)
        let filled = status != .unknown && status != .checking
        return ZStack {
            Circle()
                .fill(filled ? color : Color.clear)
            Circle()
                .strokeBorder(isCurrent ? OnboardingTheme.accent : color, lineWidth: isCurrent ? 2 : 1.5)
            if status == .checking {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            } else if filled {
                Image(systemName: OnboardingTheme.symbol(for: status))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.black)
            }
        }
        .frame(width: 20, height: 20)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: status)
    }

    /// The stem between two nodes; it fills once the upper step is settled.
    private func segment(after step: SetupStep) -> some View {
        let grown = progress.status(of: step).isSettled
        return ZStack(alignment: .top) {
            Capsule()
                .fill(OnboardingTheme.idle)
                .frame(width: 2)
            Capsule()
                .fill(OnboardingTheme.color(for: progress.status(of: step)))
                .frame(width: 2)
                .scaleEffect(x: 1, y: grown ? 1 : 0, anchor: .top)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8),
                    value: grown
                )
        }
        .frame(width: 20, height: 22)
        .accessibilityHidden(true)
    }
}
