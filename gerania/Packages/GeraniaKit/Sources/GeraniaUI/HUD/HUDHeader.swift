import GeraniaCore
import SwiftUI

/// The header of the HUD: orb, state word and the two small actions.
public struct HUDHeader: View {
    private let model: HUDViewModel

    public init(model: HUDViewModel) {
        self.model = model
    }

    private var hasAnswer: Bool {
        !model.streamedText.isEmpty || !model.tools.isEmpty || !model.reasoningText.isEmpty
    }

    private var title: String {
        if model.isLive, case .listening = model.state {
            return "Диалог"
        }
        return model.state.displayName
    }

    public var body: some View {
        HStack(spacing: 7) {
            GeraOrb(state: model.state, level: model.micLevel)
            Text(title)
                .font(HUDTheme.titleFont)
                .foregroundStyle(HUDTheme.textPrimary)
                .lineLimit(1)
            if model.showsModel, let label = model.modelLabel, !label.isEmpty {
                ModelBadge(text: label)
            }
            Spacer(minLength: 8)
            if hasAnswer {
                HeaderButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Развернуть ответ") {
                    model.onAction?(.expandAnswer)
                }
            }
            HeaderButton(symbol: "xmark", help: "Закрыть (Esc)") {
                model.onAction?(.closePanel)
            }
        }
        .frame(height: 24)
    }
}

/// Name of the model that answers: a quiet pill next to the state word.
private struct ModelBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(HUDTheme.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: 150)
            .background {
                Capsule(style: .continuous)
                    .fill(HUDTheme.controlFill)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(HUDTheme.controlBorder, lineWidth: 0.5)
            }
            .help("Модель, которая отвечает сейчас")
    }
}

/// Tiny monochrome action in the header: grey by default, white on hover.
private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(isHovering ? HUDTheme.textPrimary : HUDTheme.textSecondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}
