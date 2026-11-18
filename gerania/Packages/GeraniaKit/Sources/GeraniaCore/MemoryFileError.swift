import Foundation

/// A problem with a memory file, explained for the settings window.
public enum MemoryFileError: Error, LocalizedError, Equatable {
    /// The person tried to save an empty entry.
    case emptyEntry
    /// An entry contains the `§` delimiter and would split in two.
    case delimiterInEntry
    /// The new content does not fit into the character budget.
    case overLimit(kind: MemoryKind, limit: Int, characters: Int)
    /// The file changed after it was read; saving would lose the other change.
    case changedExternally(fileName: String)
    /// The file exists but cannot be read.
    case unreadable(fileName: String)
    /// The write failed.
    case writeFailed(fileName: String, reason: String)
    /// Another program holds the lock.
    case busy(fileName: String)
    /// The entry was removed by another window.
    case missingEntry

    public var errorDescription: String? {
        switch self {
        case .emptyEntry:
            "Запись пустая: напишите хотя бы одну букву."
        case .delimiterInEntry:
            "Запись не может содержать строку с §: это разделитель между записями."
        case let .overLimit(kind, limit, characters):
            "Не помещается в «\(kind.title)»: \(characters) из \(limit) символов. Сократите запись."
        case let .changedExternally(fileName):
            "Файл \(fileName) изменили извне. Список обновлён — проверьте запись и повторите."
        case let .unreadable(fileName):
            "Не удалось прочитать \(fileName). Файл не изменён."
        case let .writeFailed(fileName, reason):
            "Не удалось записать \(fileName): \(reason)"
        case let .busy(fileName):
            "Файл \(fileName) занят другой программой. Попробуйте ещё раз."
        case .missingEntry:
            "Запись уже удалена. Список обновлён."
        }
    }
}
