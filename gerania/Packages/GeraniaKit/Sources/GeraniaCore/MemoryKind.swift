import Foundation

/// The two files of the curated Hermes memory.
///
/// Hermes keeps a profile of the person in `USER.md` and its own notes in
/// `MEMORY.md`. Entries are plain text separated by `\n§\n`; both files are
/// injected into the system prompt when a session starts.
public enum MemoryKind: String, CaseIterable, Sendable, Identifiable {
    /// `USER.md`: who the person is.
    case user
    /// `MEMORY.md`: what the agent learned.
    case notes

    public var id: String {
        rawValue
    }

    public var fileName: String {
        switch self {
        case .user: "USER.md"
        case .notes: "MEMORY.md"
        }
    }

    public var title: String {
        switch self {
        case .user: "О пользователе"
        case .notes: "Заметки Геры"
        }
    }

    public var subtitle: String {
        switch self {
        case .user: "Имя, город, учёба, стек и стиль ответов"
        case .notes: "Что Гера запомнила сама"
        }
    }

    /// Character budget of the file; mirrors Hermes' defaults.
    public var limit: Int {
        switch self {
        case .user: 1375
        case .notes: 2200
        }
    }

    /// Name of the target in the Hermes `memory` tool.
    public var toolTarget: String {
        switch self {
        case .user: "user"
        case .notes: "memory"
        }
    }

    /// Separator Hermes writes between entries.
    public static let delimiter = "\n§\n"
}
