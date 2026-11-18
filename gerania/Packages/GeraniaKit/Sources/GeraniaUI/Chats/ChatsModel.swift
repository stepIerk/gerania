import Foundation
import GeraniaCore
import HermesKit
import Observation

/// State of the chat list: the current session, the recent ones and the search.
///
/// The list is refreshed when it opens, after every answer and once a minute while it
/// stays open.
@MainActor
@Observable
public final class ChatsModel {
    /// Recent sessions of the user.
    public private(set) var sessions: [SessionSummary] = []
    /// Whether the list is being loaded right now.
    public private(set) var isLoading = false
    /// Last error of the list.
    public private(set) var lastError: String?
    /// Search query over the title, the preview and the id.
    public var query = ""
    /// Whether the chat list is open.
    public private(set) var isListOpen = false
    /// Position of the highlighted row.
    public private(set) var selectedIndex = 0

    private let settings: GeraSettings
    private let now: @Sendable () -> Date
    private weak var service: ChatsService?
    private var autoRefreshTask: Task<Void, Never>?

    public init(settings: GeraSettings, now: @escaping @Sendable () -> Date = { Date() }) {
        self.settings = settings
        self.now = now
    }

    /// Identifier of the current session.
    public var currentSessionID: String {
        settings.lastSessionID
    }

    /// The current session in the list.
    public var currentSession: SessionSummary? {
        sessions.first { $0.id == currentSessionID }
    }

    /// Whether the backend can rename a session.
    public var canRename: Bool {
        service?.supportsRenaming ?? false
    }

    /// Sessions that match the query.
    public var filteredSessions: [SessionSummary] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(query)
                || session.preview.localizedCaseInsensitiveContains(query)
                || session.id.localizedCaseInsensitiveContains(query)
        }
    }

    /// Filtered sessions split into the sections of the picker.
    public var sections: [ChatSection] {
        ChatSections.group(filteredSessions, now: now())
    }

    /// Attaches the source of the sessions.
    public func attach(service: ChatsService) {
        self.service = service
    }

    /// Reloads the list.
    public func refresh() async {
        guard let service else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = await service.listSessions()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Opens the list and starts the background refresh.
    public func openList() async {
        isListOpen = true
        selectedIndex = 0
        await refresh()
        startAutoRefresh()
    }

    /// Closes the list and stops the background refresh.
    public func closeList() {
        isListOpen = false
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    /// Makes the session current.
    public func select(sessionID: String) {
        settings.lastSessionID = sessionID
    }

    /// Starts a new chat: the current session is forgotten.
    public func newChat() {
        settings.lastSessionID = ""
    }

    /// Renames the session through the official method of the protocol.
    public func rename(sessionID: String, title: String) async {
        guard let service else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await service.renameSession(id: sessionID, title: trimmed)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Moves the highlight inside the list.
    public func moveSelection(by offset: Int) {
        let count = filteredSessions.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + offset, 0), count - 1)
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self, self.isListOpen else { return }
                await self.refresh()
            }
        }
    }
}
