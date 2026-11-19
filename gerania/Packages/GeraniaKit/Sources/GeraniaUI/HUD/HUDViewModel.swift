import Foundation
import GeraniaCore
import Observation

/// Observable state of the HUD panel.
///
/// The model owns the streamed answer: deltas arrive one by one, the `StreamBuffer`
/// throttles them to thirty snapshots per second and only the tail block of the
/// markdown is re-rendered.
@MainActor
@Observable
public final class HUDViewModel {
    /// Current state of the assistant.
    public var state: GeraState = .idle
    /// Whether the HUD card is on screen.
    public var isVisible = false
    /// Whether the microphone belongs to the live Gemini dialog.
    public var isLive = false
    /// The live dialog does not send the microphone now (push-to-talk, another voice).
    public var isLiveMicClosed = false
    /// Short name of the model that answers the current turn.
    public var modelLabel: String?
    /// Whether the header shows `modelLabel`.
    public var showsModel = false
    /// Raw text of the answer as it was received.
    public private(set) var streamedText: String = ""
    /// Reasoning of the model, shown in a collapsible block.
    public private(set) var reasoningText: String = ""
    /// Tools that are running or have finished.
    public private(set) var tools: [ToolChip] = []
    /// Finished markdown blocks, rendered once.
    public private(set) var blocks: [String] = []
    /// Markdown block that is still growing.
    public private(set) var tail: String = ""
    /// Approval request waiting for an answer.
    public var approval: ServerRequest?
    /// Detailed error output shown on demand.
    public var errorDetails: String?
    /// Whether the panel is expanded with the error details.
    public var showsErrorDetails = false
    /// Whether the panel is pinned and does not hide itself.
    public var isPinned = false
    /// Text of the recognized command, shown with a typewriter effect.
    public var heardText: String?
    /// Short hint shown under the answer, for example the steps to paste a session id.
    public var hint: String?
    /// When the hint stops being shown.
    public var hintExpiresAt: Date?
    /// Reminder shown after ten minutes of driving the computer.
    public var computerUseNotice: String?

    /// Whether a `computer_use` call is running right now.
    public var isComputerUseActive: Bool {
        tools.contains { $0.isComputerUse && !$0.isFinished }
    }

    /// Whether the hint is still on screen.
    public var isHintVisible: Bool {
        guard let hintExpiresAt else { return false }
        return hintExpiresAt > Date()
    }

    /// Microphone level, 0...1.
    public var micLevel: Float = 0
    /// Whether the answer view follows the bottom of the text.
    public var isFollowing = true
    @ObservationIgnored public var onHover: ((Bool) -> Void)?
    @ObservationIgnored public var onAction: ((HUDAction) -> Void)?
    @ObservationIgnored public var onHeightChange: ((CGFloat) -> Void)?
    @ObservationIgnored private var buffer = StreamBuffer()

    public init() {}

    /// Reports the height of the whole card, measured by the view.
    public func reportHeight(_ height: CGFloat) {
        guard height > 1 else { return }
        onHeightChange?(max(height, HUDTheme.minHeight))
    }

    /// Adds a chunk of the answer and republishes the snapshot when the throttle allows.
    public func appendDelta(_ delta: String) {
        guard let snapshot = buffer.append(delta) else { return }
        publish(snapshot)
    }

    /// Publishes the whole answer, ignoring the throttle.
    public func flushStream() {
        publish(buffer.flush())
    }

    /// Clears the answer before a new turn.
    public func reset() {
        buffer.reset()
        streamedText = ""
        reasoningText = ""
        tools = []
        blocks = []
        tail = ""
        approval = nil
        errorDetails = nil
        showsErrorDetails = false
        computerUseNotice = nil
        isFollowing = true
    }

    /// Adds a piece of reasoning.
    public func appendReasoning(_ delta: String) {
        reasoningText += delta
    }

    /// Registers a started tool.
    public func startTool(_ chip: ToolChip) {
        tools.removeAll { $0.id == chip.id }
        tools.append(chip)
    }

    /// Attaches what a tool returned without closing it yet.
    public func attachOutput(id: String, imagePath: String?, summary: String?) {
        guard let index = tools.firstIndex(where: { $0.id == id }) else { return }
        tools[index] = tools[index].withOutput(imagePath: imagePath, summary: summary)
    }

    /// Marks a tool as finished.
    public func finishTool(id: String, ok: Bool) {
        guard let index = tools.firstIndex(where: { $0.id == id }) else { return }
        tools[index] = tools[index].finished(ok: ok)
    }

    private func publish(_ text: String) {
        streamedText = text
        HUDProfiler.measure("hud.publish") {
            let markdown = MarkdownStreamSanitizer.sanitize(text)
            let split = MarkdownBlockSplitter.split(markdown)
            blocks = split.completed
            tail = split.tail
        }
    }
}
