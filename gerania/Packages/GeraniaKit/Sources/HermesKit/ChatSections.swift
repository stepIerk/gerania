import Foundation

/// Section of the chat list.
public enum ChatSectionKind: String, Sendable, Equatable, CaseIterable {
    case today
    case yesterday
    case earlier

    /// Title shown above the section.
    public var title: String {
        switch self {
        case .today: "Сегодня"
        case .yesterday: "Вчера"
        case .earlier: "Ранее"
        }
    }
}

/// Chats of one section.
public struct ChatSection: Sendable, Equatable {
    public let kind: ChatSectionKind
    public let sessions: [SessionSummary]

    public init(kind: ChatSectionKind, sessions: [SessionSummary]) {
        self.kind = kind
        self.sessions = sessions
    }
}

/// Splits the chat list into the sections of the picker.
public enum ChatSections {
    /// Groups the sessions by the day of their last activity.
    public static func group(
        _ sessions: [SessionSummary],
        now: Date,
        calendar: Calendar = .current
    ) -> [ChatSection] {
        let sorted = sessions.sorted { lhs, rhs in
            (lhs.updatedAt ?? lhs.startedAt ?? .distantPast)
                > (rhs.updatedAt ?? rhs.startedAt ?? .distantPast)
        }
        var buckets: [ChatSectionKind: [SessionSummary]] = [:]
        for session in sorted {
            let kind = kind(for: session, now: now, calendar: calendar)
            buckets[kind, default: []].append(session)
        }
        return ChatSectionKind.allCases.compactMap { kind in
            guard let items = buckets[kind], !items.isEmpty else { return nil }
            return ChatSection(kind: kind, sessions: items)
        }
    }

    /// Section of a single session.
    public static func kind(
        for session: SessionSummary,
        now: Date,
        calendar: Calendar = .current
    ) -> ChatSectionKind {
        guard let date = session.updatedAt ?? session.startedAt else { return .earlier }
        if calendar.isDate(date, inSameDayAs: now) {
            return .today
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        if calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        return .earlier
    }
}
