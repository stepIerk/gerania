import Foundation

/// Gemini Live models Gerania offers, in fallback order.
///
/// Ids are taken from the Gemini API models page (November 2026). The free key
/// limits every model separately (about 65k tokens a minute), so when one model
/// runs out the next one usually still answers.
public enum LiveModelCatalog {
    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let note: String
    }

    public static let entries: [Entry] = [
        Entry(id: "gemini-3.8-live", title: "Gemini 3.8 Live", note: "Основная: быстрый живой ответ"),
        Entry(
            id: "gemini-3.8-live-extended-thinking",
            title: "Gemini 3.8 Live, с размышлениями",
            note: "Думает перед ответом: умнее, но паузы длиннее"
        ),
        Entry(id: "gemini-3.1-flash-live-preview", title: "Gemini 3.1 Flash Live", note: "Запасная, preview"),
        Entry(
            id: "gemini-2.5-flash-native-audio-preview-12-2025",
            title: "Gemini 2.5 Flash Live",
            note: "Запасная, предыдущее поколение"
        ),
    ]

    public static let defaultModel = "gemini-3.8-live"

    /// The chosen model first, then the catalog without it. Extended thinking
    /// falls back to the plain 3.8 Live, which is first in the catalog anyway.
    public static func chain(startingWith preferred: String) -> [String] {
        let preferred = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = entries.map(\.id)
        guard !preferred.isEmpty else { return catalog }
        return [preferred] + catalog.filter { $0 != preferred }
    }

    public static func title(of model: String) -> String {
        entries.first { $0.id == model }?.title ?? model
    }
}

/// Remembers which Live models hit their limit and when they may be tried again.
///
/// A per-minute limit clears in a minute; a model that runs out again soon after
/// probably hit a daily limit, so its pause grows to ten minutes and then an hour.
public struct LiveQuotaGuard: Sendable, Equatable {
    private var blockedUntil: [String: Date] = [:]
    private var strikes: [String: Int] = [:]

    public init() {}

    public static let pauses: [TimeInterval] = [60, 600, 3600]

    public mutating func markExhausted(_ model: String, now: Date = Date()) {
        let strike = min((strikes[model] ?? 0) + 1, Self.pauses.count)
        strikes[model] = strike
        blockedUntil[model] = now.addingTimeInterval(Self.pauses[strike - 1])
    }

    /// A successful dialog resets the strikes of its model.
    public mutating func markWorking(_ model: String) {
        strikes[model] = nil
        blockedUntil[model] = nil
    }

    public func isAvailable(_ model: String, now: Date = Date()) -> Bool {
        guard let until = blockedUntil[model] else { return true }
        return now >= until
    }

    /// The first model of the chain that is not paused, `nil` when all are.
    public func pick(preferred: String, now: Date = Date()) -> String? {
        LiveModelCatalog.chain(startingWith: preferred).first { isAvailable($0, now: now) }
    }

    /// When the earliest paused model of the chain frees up.
    public func nextAvailableDate(preferred: String) -> Date? {
        LiveModelCatalog.chain(startingWith: preferred).compactMap { blockedUntil[$0] }.min()
    }
}
