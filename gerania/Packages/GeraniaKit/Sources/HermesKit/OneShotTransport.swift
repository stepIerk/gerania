import Foundation
import GeraniaCore

private struct OneShotResult {
    let status: Int32
    let text: String
    let stderr: String
}

public actor OneShotTransport: HermesTransport {
    public nonisolated let kind: TransportKind = .oneshot

    public typealias CommandBuilder = @Sendable (_ prompt: String, _ continueSession: Bool) -> (URL, [String])

    private let config: HermesConfig
    private let commandBuilder: CommandBuilder?
    private var current: ChildProcess?
    private var activeContinuation: AsyncThrowingStream<HermesEvent, Error>.Continuation?
    private var terminated = false

    public init(config: HermesConfig) {
        self.config = config
        commandBuilder = nil
    }

    init(config: HermesConfig, commandBuilder: @escaping CommandBuilder) {
        self.config = config
        self.commandBuilder = commandBuilder
    }

    public func connect() async throws {
        guard commandBuilder != nil || (try? config.hermesBinary()) != nil else {
            throw HermesError.binaryNotFound
        }
    }

    public func listSessions(limit: Int) async throws -> [SessionSummary] {
        throw HermesError.notConfigured("one-shot не хранит список сессий")
    }

    public func newSession(title: String?) async throws -> SessionID {
        "oneshot-\(UUID().uuidString.lowercased())"
    }

    public nonisolated func send(
        _ text: String,
        session: SessionID?,
        mode: PromptMode
    ) -> AsyncThrowingStream<HermesEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination else { return }
                Task { await self?.cancelCurrent() }
            }
            Task {
                await self.performTurn(text, session: session, mode: mode, continuation: continuation)
            }
        }
    }

    public func interrupt(session: SessionID) async {
        await cancelCurrent()
    }

    public func respond(to request: ServerRequest, with answer: ServerRequestAnswer) async throws {
        throw HermesError.protocolError("one-shot не поддерживает интерактивные запросы")
    }

    public func close() async {
        await cancelCurrent()
    }

    private func performTurn(
        _ text: String,
        session: SessionID?,
        mode: PromptMode,
        continuation: AsyncThrowingStream<HermesEvent, Error>.Continuation
    ) async {
        if current != nil {
            await cancelCurrent()
        }
        activeContinuation = continuation
        terminated = false
        let sid = session ?? "oneshot-\(Int(Date().timeIntervalSince1970))"
        continuation.yield(.sessionBound(sid))

        do {
            let prompt = config.prompt(for: text, mode: mode)
            let continueSession = session != nil && !sid.hasPrefix("oneshot-")
            var result = try await runOnce(prompt, continueSession: continueSession, continuation: continuation)
            if result.status == 2, continueSession, !terminated {
                result = try await runOnce(prompt, continueSession: false, continuation: continuation)
            }
            activeContinuation = nil
            if terminated || result.status == 143 || result.status == 130 {
                continuation.yield(.cancelled)
            } else if result.status == 0 {
                continuation.yield(.completed(finalText: result.text))
            } else {
                continuation.yield(.failed(.processFailed(
                    exitCode: result.status,
                    message: result.stderr.isEmpty ? "нет вывода ошибки" : result.stderr
                )))
            }
        } catch {
            activeContinuation = nil
            continuation.yield(.failed(error as? HermesError ?? .protocolError(error.localizedDescription)))
        }
        continuation.finish()
    }

    private func runOnce(
        _ prompt: String,
        continueSession: Bool,
        continuation: AsyncThrowingStream<HermesEvent, Error>.Continuation
    ) async throws -> OneShotResult {
        let command: (URL, [String])
        if let commandBuilder {
            command = commandBuilder(prompt, continueSession)
        } else {
            let binary = try config.hermesBinary()
            var arguments = ["-z", prompt]
            if !config.provider.isEmpty {
                arguments += ["--provider", config.provider]
            }
            if !config.model.isEmpty {
                arguments += ["-m", config.model]
            }
            if continueSession {
                arguments.append("--continue")
            }
            command = (binary, arguments)
        }

        let process = try ChildProcess(
            executable: command.0,
            arguments: command.1,
            environment: config.processEnvironment(),
            currentDirectory: config.expandedWorkdir
        )
        current = process

        let stdoutTask = Task {
            await Self.readLines(process.stdout) { text in
                continuation.yield(.textDelta(text))
            }
        }
        let stderrTask = Task {
            await Self.readAll(process.stderr)
        }
        let status = await process.wait()
        let text = await stdoutTask.value
        let stderr = await stderrTask.value
        if current === process {
            current = nil
        }
        return OneShotResult(
            status: status,
            text: text,
            stderr: String(stderr.suffix(2000)).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func cancelCurrent() async {
        guard let process = current else { return }
        terminated = true
        process.terminate()
        Task { [weak self, weak process] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, let process else { return }
            if await self.isCurrent(process) {
                process.forceKill()
            }
        }
    }

    private func isCurrent(_ process: ChildProcess) -> Bool {
        current === process
    }

    private static func readLines(
        _ handle: FileHandle,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> String {
        var buffer = Data()
        var text = ""
        for await chunk in FileHandleChunks.stream(handle) {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[...newline])
                buffer.removeSubrange(...newline)
                let string = String(data: line, encoding: .utf8) ?? ""
                text += string
                onLine(string)
            }
        }
        if !buffer.isEmpty {
            let string = String(data: buffer, encoding: .utf8) ?? ""
            text += string
            onLine(string)
        }
        return text
    }

    private static func readAll(_ handle: FileHandle) async -> String {
        var data = Data()
        for await chunk in FileHandleChunks.stream(handle) {
            data.append(chunk)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
