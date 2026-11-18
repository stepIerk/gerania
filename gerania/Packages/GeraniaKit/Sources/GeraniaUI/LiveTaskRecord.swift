import Foundation
import GeraniaCore
import HermesKit

/// Mutable state of one live task.
@MainActor
final class LiveTaskRecord {
    let id: String
    let title: String
    let goal: String
    var status: LiveTaskSnapshot.Status = .queued
    var summary: String?
    var session: SessionID?
    var manager: TransportManager?
    var task: Task<Void, Never>?
    var approval: ServerRequest?
    var approvalTask: Task<Void, Never>?
    var pendingInstruction: String?

    init(id: String, title: String, goal: String) {
        self.id = id
        self.title = title
        self.goal = goal
    }

    func takeInstruction() -> String? {
        defer { pendingInstruction = nil }
        return pendingInstruction
    }

    static func defaultTitle(for goal: String) -> String {
        let words = goal
            .split(separator: " ", omittingEmptySubsequences: true)
            .prefix(5)
            .joined(separator: " ")
        return words.isEmpty ? "Задача" : String(words.prefix(60))
    }
}
