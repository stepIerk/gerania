import Foundation
import GeraniaCore

public actor TransportManager {
    public let config: HermesConfig
    public let requestedKind: TransportKind
    public private(set) var resolvedKind: TransportKind?
    public private(set) var fallbackReason: String?
    public private(set) var lastSessionID: SessionID?

    private var active: (any HermesTransport)?

    public init(config: HermesConfig, kind: TransportKind = .auto) {
        self.config = config
        requestedKind = kind
    }

    public func connect() async throws {
        if active != nil {
            return
        }
        switch requestedKind {
        case .gateway:
            try await select(GatewayTransport(config: config))
        case .acp:
            try await select(ACPTransport(config: config))
        case .oneshot:
            try await select(OneShotTransport(config: config))
        case .auto:
            try await connectAutomatically()
        }
    }

    public nonisolated func send(
        _ text: String,
        session: SessionID?,
        mode: PromptMode
    ) -> AsyncThrowingStream<HermesEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination else { return }
                Task {
                    if let sid = await self?.lastSessionID {
                        await self?.interrupt(session: sid)
                    }
                }
            }
            Task {
                await self.forward(text, session: session, mode: mode, continuation: continuation)
            }
        }
    }

    public func sessions(limit: Int = 50) async throws -> [SessionSummary] {
        try await connect()
        guard let active else {
            throw HermesError.connectionFailed("нет активного транспорта")
        }
        return try await SessionStore(config: config, transport: active)
            .listSessions(limit: limit)
    }

    public func newSession(title: String?) async throws -> SessionID {
        try await connect()
        guard let active else {
            throw HermesError.connectionFailed("нет активного транспорта")
        }
        let sid = try await active.newSession(title: title)
        lastSessionID = sid
        return sid
    }

    public func interrupt(session: SessionID) async {
        await active?.interrupt(session: session)
    }

    public func respond(
        to request: ServerRequest,
        with answer: ServerRequestAnswer
    ) async throws {
        try await connect()
        guard let active else {
            throw HermesError.connectionFailed("нет активного транспорта")
        }
        try await active.respond(to: request, with: answer)
    }

    /// Whether the active transport can rename a session.
    public func supportsRenaming() async -> Bool {
        active?.supportsRenaming ?? false
    }

    /// Renames the session through the active transport.
    public func renameSession(id: SessionID, title: String) async throws {
        try await connect()
        guard let active else {
            throw HermesError.transportUnavailable(.auto)
        }
        try await active.renameSession(id: id, title: title)
    }

    public func close() async {
        await active?.close()
        active = nil
        resolvedKind = nil
    }

    private func connectAutomatically() async throws {
        var reasons: [String] = []
        do {
            try await select(GatewayTransport(config: config))
            return
        } catch {
            reasons.append("Gateway: \(error.localizedDescription)")
        }
        do {
            try await select(ACPTransport(config: config))
            return
        } catch {
            reasons.append("ACP: \(error.localizedDescription)")
        }
        do {
            try await select(OneShotTransport(config: config))
        } catch {
            reasons.append("One-shot: \(error.localizedDescription)")
            fallbackReason = reasons.joined(separator: "; ")
            throw HermesError.transportUnavailable(.auto)
        }
        fallbackReason = reasons.joined(separator: "; ")
    }

    private func select(_ transport: any HermesTransport) async throws {
        do {
            try await transport.connect()
            active = transport
            resolvedKind = transport.kind
        } catch {
            await transport.close()
            if requestedKind != .auto {
                fallbackReason = error.localizedDescription
            }
            throw error
        }
    }

    private func forward(
        _ text: String,
        session: SessionID?,
        mode: PromptMode,
        continuation: AsyncThrowingStream<HermesEvent, Error>.Continuation
    ) async {
        do {
            try await connect()
            guard let active else {
                throw HermesError.connectionFailed("нет активного транспорта")
            }
            if let session {
                lastSessionID = session
            }
            for try await event in active.send(text, session: session, mode: mode) {
                if case let .sessionBound(sid) = event {
                    lastSessionID = sid
                }
                continuation.yield(event)
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
