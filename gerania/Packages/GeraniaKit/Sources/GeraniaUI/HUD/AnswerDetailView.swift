import SwiftUI

/// Full answer in a large black window beside the notch HUD.
///
/// The compact HUD shows only the beginning of the answer; this view is the comfortable
/// reading surface with the complete markdown, the reasoning and the tool calls.
public struct AnswerDetailView: View {
    private let model: HUDViewModel
    private let onClose: () -> Void

    public init(model: HUDViewModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(HUDTheme.hairline)
                .frame(height: 0.5)
            content
            footer
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            GeraOrb(state: model.state, level: model.micLevel)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HUDTheme.textPrimary)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Закрыть (Esc)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let details = model.errorDetails, !details.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(details)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(model.blocks.enumerated()), id: \.offset) { _, block in
                        MarkdownStreamView(markdown: block)
                    }
                    if !model.tail.isEmpty {
                        MarkdownStreamView(markdown: model.tail)
                    }
                    if !model.tools.isEmpty {
                        ToolTimelineView(tools: model.tools)
                    }
                    if !model.reasoningText.isEmpty {
                        reasoning
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var reasoning: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Рассуждения")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(HUDTheme.textSecondary)
            Text(model.reasoningText)
                .font(.system(size: 12))
                .foregroundStyle(HUDTheme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            footerButton("doc.on.doc", "Копировать", .copyAnswer)
            footerButton(
                model.state == .speaking ? "speaker.slash" : "speaker.wave.2",
                "Озвучить",
                .toggleSpeech
            )
            footerButton("macwindow", "Открыть в Hermes Desktop", .openInDesktop)
            footerButton("terminal", "Открыть в Терминале", .openInTerminal)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HUDTheme.hairline)
                .frame(height: 0.5)
        }
    }

    private func footerButton(_ symbol: String, _ help: String, _ action: HUDAction) -> some View {
        Button {
            model.onAction?(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(HUDTheme.textSecondary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var title: String {
        model.state.displayName
    }
}
