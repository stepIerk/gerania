import Foundation

/// Answers of the acquaintance form, turned into `USER.md` entries.
///
/// The form is deliberately small: name, city, study or work, stack, answer
/// style and a free note. Empty answers are skipped, so a person can fill only
/// what they want the agent to know. The time zone is taken from the Mac, not
/// asked: it is already there.
public struct MemoryProfileDraft: Sendable, Equatable {
    public var name: String
    public var city: String
    public var study: String
    public var stack: String
    public var style: String
    public var notes: String

    public init(
        name: String = "",
        city: String = "",
        study: String = "",
        stack: String = "",
        style: String = "",
        notes: String = ""
    ) {
        self.name = name
        self.city = city
        self.study = study
        self.stack = stack
        self.style = style
        self.notes = notes
    }

    /// Entries for `USER.md`, in the order the form asks the questions.
    public func entries(timeZone: TimeZone = .current) -> [String] {
        var result: [String] = []
        if let name = Self.clean(name) {
            result.append(Self.sentence("Обращаться", name))
        }
        if let city = Self.clean(city) {
            result.append(Self.sentence("Город", city) + " Часовой пояс: \(timeZone.identifier).")
        }
        if let study = Self.clean(study) {
            result.append(Self.sentence("Учёба и работа", study))
        }
        if let stack = Self.clean(stack) {
            result.append(Self.sentence("Стек", stack))
        }
        if let style = Self.clean(style) {
            result.append(Self.sentence("Стиль ответов", style))
        }
        if let notes = Self.clean(notes) {
            result.append(Self.sentence("Ещё", notes))
        }
        return result
    }

    private static func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sentence(_ label: String, _ value: String) -> String {
        let endsWithPunctuation = value.hasSuffix(".") || value.hasSuffix("!") || value.hasSuffix("?")
        return "\(label): \(value)\(endsWithPunctuation ? "" : ".")"
    }
}
