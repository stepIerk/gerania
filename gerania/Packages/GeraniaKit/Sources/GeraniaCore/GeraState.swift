import Foundation

/// Single source of truth for the HUD / menu-bar state.
public enum GeraState: Sendable, Equatable {
    case idle
    case listening(deadline: TimeInterval)
    case transcribing
    case thinking(tools: [ToolChip])
    case streaming
    case speaking
    case done
    case error(String)
    case awaitingApproval(ServerRequest)

    public var isBusy: Bool {
        switch self {
        case .thinking, .streaming, .speaking, .awaitingApproval, .transcribing:
            true
        case .idle, .listening, .done, .error:
            false
        }
    }

    public var isInterruptible: Bool {
        switch self {
        case .thinking, .streaming, .speaking, .awaitingApproval:
            true
        case .idle, .listening, .transcribing, .done, .error:
            false
        }
    }

    public var displayName: String {
        switch self {
        case .idle: "Готова"
        case .listening: "Слушаю"
        case .transcribing: "Распознаю"
        case .thinking: "Думаю"
        case .streaming: "Отвечаю"
        case .speaking: "Говорю"
        case .done: "Готово"
        case .error: "Ошибка"
        case .awaitingApproval: "Подтвердить"
        }
    }
}
