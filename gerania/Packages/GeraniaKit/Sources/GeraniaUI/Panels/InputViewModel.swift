import Foundation
import GeraniaCore
import HermesKit
import Observation

/// State of the mini window with the text input.
///
/// The model owns the text, the history and the current chat; the list of chats lives in
/// `ChatsModel`.
@MainActor
@Observable
public final class InputViewModel {
    /// Text typed by the user.
    public var text: String = ""
    /// Name of the current chat.
    public var chatTitle: String = "Новый чат"
    /// Incremented on every show, so the view can move the focus into the field.
    public var focusToken = 0
    /// Whether the panel is shown. The controller drives the bottom spring reveal.
    public var isVisible = false

    /// History of the sent prompts.
    public private(set) var history: PromptHistory
    /// Position inside the history while the user browses it.
    public private(set) var historyCursor: Int?

    @ObservationIgnored public var onSend: ((String, Bool) -> Void)?
    @ObservationIgnored public var onClose: (() -> Void)?
    @ObservationIgnored public var onOpenChatList: (() -> Void)?
    @ObservationIgnored public var onNewChat: (() -> Void)?
    @ObservationIgnored public var onSelectChat: ((String) -> Void)?
    @ObservationIgnored public var onPushToTalk: (() -> Void)?
    @ObservationIgnored public var onRename: ((SessionSummary) -> Void)?
    @ObservationIgnored public var onOpenInDesktop: ((String) -> Void)?
    @ObservationIgnored public var onHeightChange: ((CGFloat) -> Void)?
    @ObservationIgnored public var onWidthChange: ((CGFloat) -> Void)?

    /// The window grows with long lines but stays compact.
    public static let baseWidth = InputDesign.totalWidth(fieldWidth: InputDesign.baseFieldWidth)
    public static let maximumWidth = InputDesign.totalWidth(fieldWidth: InputDesign.maximumFieldWidth)
    public static var baseHeight: CGFloat {
        InputDesign.baseHeight
    }

    /// Width of the field for the current text.
    public var fieldWidth: CGFloat {
        let longest = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(\.count)
            .max() ?? 0
        let extra = CGFloat(max(0, longest - 26)) * 6.5
        return min(InputDesign.maximumFieldWidth, InputDesign.baseFieldWidth + extra)
    }

    /// Width of the whole bottom panel for the current text.
    public var preferredWidth: CGFloat {
        InputDesign.totalWidth(fieldWidth: fieldWidth)
    }

    /// Width available inside the transparent edge padding.
    public var contentWidth: CGFloat {
        preferredWidth - InputDesign.edge * 2
    }

    public init(history: PromptHistory = PromptHistory()) {
        self.history = history
    }

    /// Whether the send button is active.
    public var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Handles a key command of the mini window.
    public func handle(_ command: InputKeyCommand) {
        switch command {
        case .send:
            send()
        case .sendInNewChat:
            sendInNewChat()
        case .newline:
            text += "\n"
        case .close:
            onClose?()
        case .previousPrompt:
            showPreviousPrompt()
        case .nextPrompt:
            showNextPrompt()
        case .openChatList:
            onOpenChatList?()
        case .newChat:
            startNewChat()
        case .none:
            break
        }
    }

    /// Sends the text to the current chat.
    public func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        text = ""
        historyCursor = nil
        onSend?(trimmed, false)
    }

    /// Sends the text to a new chat.
    public func sendInNewChat() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        text = ""
        historyCursor = nil
        onSend?(trimmed, true)
    }

    /// Remembers a prompt in the history.
    public func remember(_ prompt: String) {
        var history = history
        history.add(prompt)
        self.history = history
    }

    /// Opens the list of chats.
    public func openChatList() {
        onOpenChatList?()
    }

    /// Selects a chat by its identifier.
    public func selectChat(id: String, title: String) {
        chatTitle = title.isEmpty ? "Новый чат" : title
        onSelectChat?(id)
    }

    /// Starts a new chat.
    public func startNewChat() {
        chatTitle = "Новый чат"
        onNewChat?()
    }

    /// Asks to rename the session.
    public func requestRename(session: SessionSummary) {
        onRename?(session)
    }

    /// Asks to open the session in the Hermes Desktop.
    public func openInDesktop(sessionID: String) {
        onOpenInDesktop?(sessionID)
    }

    private func showPreviousPrompt() {
        guard text.isEmpty || historyCursor != nil, let entry = history.prompt(before: historyCursor) else { return }
        historyCursor = entry.cursor
        text = entry.prompt
    }

    private func showNextPrompt() {
        guard text.isEmpty || historyCursor != nil else { return }
        guard let entry = history.prompt(after: historyCursor) else {
            historyCursor = nil
            text = ""
            return
        }
        historyCursor = entry.cursor
        text = entry.prompt
    }
}
