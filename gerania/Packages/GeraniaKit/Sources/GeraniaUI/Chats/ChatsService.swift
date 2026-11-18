import Foundation
import HermesKit

/// Source of the chat list for `ChatsModel`.
@MainActor
public protocol ChatsService: AnyObject {
    /// Whether the backend can rename a session.
    var supportsRenaming: Bool { get }
    /// Recent sessions of the user.
    func listSessions() async -> [SessionSummary]
    /// Renames the session.
    func renameSession(id: String, title: String) async throws
}
