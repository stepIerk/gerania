import Foundation
import GeraniaCore

/// One transport over Hermes: Gateway WebSocket, ACP stdio, or one-shot CLI.
public protocol HermesTransport: Sendable {
    var kind: TransportKind { get }

    func connect() async throws
    func listSessions(limit: Int) async throws -> [SessionSummary]
    func newSession(title: String?) async throws -> SessionID
    func send(_ text: String, session: SessionID?, mode: PromptMode) -> AsyncThrowingStream<HermesEvent, Error>
    func interrupt(session: SessionID) async
    func respond(to request: ServerRequest, with answer: ServerRequestAnswer) async throws
    func close() async

    /// Renames the session, if the protocol of the transport supports it.
    func renameSession(id: SessionID, title: String) async throws

    /// Whether the protocol of the transport can rename a session.
    var supportsRenaming: Bool { get }
}

public extension HermesTransport {
    /// Only the gateway knows how to rename a session.
    var supportsRenaming: Bool {
        false
    }

    /// Transports without a rename method refuse the request.
    func renameSession(id: SessionID, title: String) async throws {
        throw HermesError.protocolError("переименование сессии не поддерживается")
    }
}
