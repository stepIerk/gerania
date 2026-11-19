import Foundation

/// A plain-text report the person can send when Gera misbehaves.
///
/// It holds facts (versions, paths, statuses) and the recent log of the app.
/// The whole text passes `SecretRedactor`, so a key that slipped into a log
/// line or a setting does not leave the machine.
public struct DiagnosticsReport: Sendable, Equatable {
    public struct Section: Sendable, Equatable {
        public let title: String
        public let rows: [(String, String)]

        public init(title: String, rows: [(String, String)]) {
            self.title = title
            self.rows = rows
        }

        public static func == (lhs: Section, rhs: Section) -> Bool {
            lhs.title == rhs.title
                && lhs.rows.map(\.0) == rhs.rows.map(\.0)
                && lhs.rows.map(\.1) == rhs.rows.map(\.1)
        }
    }

    public let createdAt: Date
    public let sections: [Section]
    public let logLines: [String]

    /// The last lines are the interesting ones; older ones only bloat the file.
    public static let maxLogLines = 3000

    public init(createdAt: Date = Date(), sections: [Section], logLines: [String]) {
        self.createdAt = createdAt
        self.sections = sections
        self.logLines = Array(logLines.suffix(Self.maxLogLines))
    }

    public var fileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "Gerania-diagnostics-\(formatter.string(from: createdAt)).txt"
    }

    public var text: String {
        var lines = [
            "Отчёт диагностики Геры",
            "Создан: \(ISO8601DateFormatter().string(from: createdAt))",
            "Ключи и токены в этом файле заменены на \(SecretRedactor.mask).",
        ]
        for section in sections {
            lines.append("")
            lines.append("## \(section.title)")
            for (name, value) in section.rows {
                lines.append("\(name): \(value)")
            }
        }
        lines.append("")
        lines.append("## Журнал приложения (\(logLines.count) строк)")
        lines.append(contentsOf: logLines.isEmpty ? ["(пусто)"] : logLines)
        return SecretRedactor.redact(lines.joined(separator: "\n")) + "\n"
    }
}
