import Foundation
import GeraniaCore
import SQLite3

public actor SessionStore {
    private let config: HermesConfig
    private let transport: any HermesTransport

    public init(config: HermesConfig, transport: any HermesTransport) {
        self.config = config
        self.transport = transport
    }

    public func listSessions(limit: Int = 50) async throws -> [SessionSummary] {
        do {
            return try await transport.listSessions(limit: limit)
        } catch {
            Log.hermes.debug(
                "session listing via transport failed: \(error.localizedDescription, privacy: .public)"
            )
            return try readDatabase(limit: limit)
        }
    }

    private func readDatabase(limit: Int) throws -> [SessionSummary] {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(config.stateDatabaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "не удалось открыть state.db"
            if let database {
                sqlite3_close(database)
            }
            throw HermesError.notConfigured(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 200)

        let sql = """
        SELECT s.id,
               COALESCE(s.title, ''),
               s.source,
               COALESCE(s.last_activity_at, s.started_at, 0),
               COALESCE(s.started_at, 0),
               COALESCE(s.message_count, 0),
               COALESCE(s.cwd, ''),
               COALESCE((
                   SELECT m.content FROM messages m
                   WHERE m.session_id = s.id AND m.role = 'user' AND m.active = 1
                   ORDER BY m.timestamp ASC LIMIT 1
               ), '')
        FROM sessions s
        WHERE s.archived = 0
        ORDER BY COALESCE(s.last_activity_at, s.started_at, 0) DESC
        LIMIT ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw HermesError.notConfigured(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(1, limit)))

        var sessions: [SessionSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPointer = sqlite3_column_text(statement, 0) else { continue }
            let id = String(cString: idPointer)
            let title = text(statement, column: 1)
            let source = text(statement, column: 2)
            let activity = sqlite3_column_double(statement, 3)
            let started = sqlite3_column_double(statement, 4)
            let messageCount = Int(sqlite3_column_int(statement, 5))
            let cwd = text(statement, column: 6)
            let preview = cleanup(text(statement, column: 7))
            sessions.append(SessionSummary(
                id: id,
                title: title.isEmpty ? preview : title,
                preview: preview,
                updatedAt: activity > 0 ? Date(timeIntervalSince1970: activity) : nil,
                source: source,
                cwd: cwd.isEmpty ? nil : cwd,
                startedAt: started > 0 ? Date(timeIntervalSince1970: started) : nil,
                messageCount: messageCount
            ))
        }
        return sessions
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }

    private func cleanup(_ value: String) -> String {
        let firstLine = value.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? value
        return String(firstLine.prefix(280))
    }
}
