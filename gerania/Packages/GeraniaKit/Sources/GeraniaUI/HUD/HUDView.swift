import GeraniaCore
import SwiftUI

/// Content of the HUD panel.
///
/// The header is the whole panel most of the time: the state word, the orb and two small
/// actions. Only listening, the answer preview and the approval request add a body.
public struct HUDView: View {
    private let model: HUDViewModel

    public init(model: HUDViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HUDHeader(model: model)
            if model.isComputerUseActive {
                computerUseBanner
            }
            body(for: model.state)
        }
        .frame(width: HUDTheme.contentWidth, alignment: .leading)
    }

    /// Amber strip that says the Mac is under Gerania's control and offers a stop.
    private var computerUseBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 10.5, weight: .medium))
            Text(model.computerUseNotice ?? "Управляю компьютером")
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Остановить") {
                model.onAction?(.stopComputerUse)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .help("Остановить управление компьютером")
        }
        .foregroundStyle(HUDTheme.computerTint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(HUDTheme.computerTint.opacity(0.14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(HUDTheme.computerTint.opacity(0.28), lineWidth: 0.5)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func body(for state: GeraState) -> some View {
        switch state {
        case .idle, .transcribing:
            EmptyView()
        case .thinking:
            toolChips
        case .listening:
            ListeningView(model: model)
            toolChips
            if let heard = model.heardText {
                HUDHeardText(text: heard)
            }
        case .streaming:
            AnswerPreview(model: model, showsCursor: true)
        case .speaking, .done:
            AnswerPreview(model: model, showsCursor: false)
        case let .error(message):
            ErrorView(model: model, message: message)
        case let .awaitingApproval(request):
            ApprovalView(model: model, request: request)
        }
    }

    /// The last three actions and a counter of the earlier ones: the full
    /// timeline lives in the answer window.
    @ViewBuilder
    private var toolChips: some View {
        if !model.tools.isEmpty {
            WrapLayout(spacing: 5) {
                ForEach(model.tools.suffix(3)) { chip in
                    ToolChipView(chip: chip)
                }
                if model.tools.count > 3 {
                    ToolOverflowChip(count: model.tools.count - 3)
                }
            }
        }
    }
}
