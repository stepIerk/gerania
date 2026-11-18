import GeraniaCore
import HermesKit
import SwiftUI

/// Bottom prompt: one glass field and four separate round glass actions.
///
/// The panel floats above the Dock instead of hanging from the notch. The chat picker
/// grows upward from the field, keeping the input row anchored to the bottom.
public struct InputView: View {
    @Bindable private var model: InputViewModel
    private let chats: ChatsModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFieldFocused: Bool
    @State private var hoveredButton: String?

    public init(model: InputViewModel, chats: ChatsModel) {
        self.model = model
        self.chats = chats
    }

    public var body: some View {
        InputGlassGroup {
            VStack(spacing: InputDesign.spacing) {
                if chats.isListOpen {
                    chatPicker
                        .transition(
                            .scale(scale: 0.97, anchor: .bottom)
                                .combined(with: .opacity)
                        )
                }
                inputRow
            }
            .frame(width: model.contentWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88),
            value: chats.isListOpen
        )
        .onChange(of: model.text) { _, _ in
            model.onWidthChange?(model.preferredWidth)
        }
        .onAppear {
            isFieldFocused = true
        }
        .onChange(of: model.focusToken) { _, _ in
            isFieldFocused = true
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            handle(.returnKey, press: press)
        }
        .onKeyPress(keys: [.escape], phases: .down) { press in
            handle(.escape, press: press)
        }
        .onKeyPress(keys: [.upArrow], phases: .down) { press in
            handle(.up, press: press)
        }
        .onKeyPress(keys: [.downArrow], phases: .down) { press in
            handle(.down, press: press)
        }
        .onKeyPress(keys: [KeyEquivalent("k")], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.handle(.openChatList)
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("n")], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.handle(.newChat)
            return .handled
        }
    }

    private var chatPicker: some View {
        ChatPickerView(input: model, chats: chats)
            .frame(maxWidth: .infinity)
            .inputGlass(
                RoundedRectangle(cornerRadius: InputDesign.panelCorner, style: .continuous)
            )
    }

    private var inputRow: some View {
        HStack(alignment: .center, spacing: InputDesign.spacing) {
            iconButton("bubble.left", help: "Чаты (⌘K)", slot: 0, fromLeading: true) {
                model.handle(.openChatList)
            }
            iconButton("plus", help: "Новый чат (⌘N)", slot: 1, fromLeading: true) {
                model.handle(.newChat)
            }
            field
            iconButton("mic.fill", help: "Говорить (⌃⌥V)", slot: 2, fromLeading: false) {
                model.onPushToTalk?()
            }
            sendButton
        }
    }

    private var field: some View {
        TextField("Спросите Геру…", text: $model.text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .lineLimit(1 ... 5)
            .focused($isFieldFocused)
            .tint(HUDTheme.accent)
            .onSubmit {
                model.handle(.send)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: InputDesign.fieldHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .inputGlass(
                RoundedRectangle(cornerRadius: InputDesign.fieldCorner, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: InputDesign.fieldCorner, style: .continuous)
                    .strokeBorder(
                        HUDTheme.accent.opacity(isFieldFocused ? 0.72 : 0),
                        lineWidth: 1.5
                    )
                    .animation(.easeOut(duration: 0.15), value: isFieldFocused)
            }
    }

    private var sendButton: some View {
        Button {
            model.handle(.send)
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(model.canSend ? Color.white : Color.primary.opacity(0.42))
                .frame(width: InputDesign.buttonSize, height: InputDesign.buttonSize)
                .contentShape(Circle())
                .inputGlass(
                    .circle,
                    tint: model.canSend ? HUDTheme.accent : nil,
                    interactive: true
                )
                .scaleEffect(hoveredButton == "send" ? 1.05 : 1)
                .animation(.spring(response: 0.26, dampingFraction: 0.7), value: hoveredButton)
        }
        .buttonStyle(InputPressStyle())
        .disabled(!model.canSend)
        .opacity(model.canSend ? 1 : 0.62)
        .animation(.easeOut(duration: 0.16), value: model.canSend)
        .onHover { hovering in
            hoveredButton = hovering ? "send" : nil
        }
        .modifier(ButtonBloom(slot: 3, fromLeading: false, isVisible: model.isVisible))
        .help("Отправить (⏎)")
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        slot: Int,
        fromLeading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary.opacity(0.82))
                .frame(width: InputDesign.buttonSize, height: InputDesign.buttonSize)
                .contentShape(Circle())
                .inputGlass(.circle, interactive: true)
                .scaleEffect(hoveredButton == symbol ? 1.05 : 1)
                .animation(.spring(response: 0.26, dampingFraction: 0.7), value: hoveredButton)
        }
        .buttonStyle(InputPressStyle())
        .onHover { hovering in
            hoveredButton = hovering ? symbol : nil
        }
        .modifier(ButtonBloom(slot: slot, fromLeading: fromLeading, isVisible: model.isVisible))
        .help(help)
    }

    private func handle(_ key: InputKey, press: KeyPress) -> KeyPress.Result {
        let command = InputKeyParser.command(
            for: key,
            shift: press.modifiers.contains(.shift),
            command: press.modifiers.contains(.command),
            option: press.modifiers.contains(.option)
        )
        model.handle(command)
        return .handled
    }
}

/// Buttons bloom out of the glass when the panel appears: a short blur, a small
/// offset and a spring give the cluster the liquid feel of macOS 26 without a
/// timeline or extra layers.
private struct ButtonBloom: ViewModifier {
    let slot: Int
    let fromLeading: Bool
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible ? 1 : 0.58)
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible ? 0 : 7)
            .offset(x: isVisible ? 0 : (fromLeading ? 16 : -16))
            .animation(
                reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.74)
                    .delay(Double(slot) * 0.045),
                value: isVisible
            )
    }
}

/// A short, damped press like the system glass controls.
private struct InputPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.66),
                value: configuration.isPressed
            )
    }
}
