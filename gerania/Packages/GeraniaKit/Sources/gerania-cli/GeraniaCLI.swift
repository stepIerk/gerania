import Darwin
import Foundation
import GeraniaCore
import HermesKit

@main
struct GeraniaCLI {
    static func main() async {
        do {
            let code = try await run(arguments: Array(CommandLine.arguments.dropFirst()))
            exit(code)
        } catch {
            CLIOutput.writeError("Ошибка: \(error.localizedDescription)\n")
            exit(1)
        }
    }

    private static func run(arguments: [String]) async throws -> Int32 {
        guard let command = arguments.first else {
            CLIOutput.printUsage()
            return 0
        }
        if command == "--help" || command == "-h" || command == "help" {
            CLIOutput.printUsage()
            return 0
        }
        if command == "sessions" {
            return try await listSessions(arguments: Array(arguments.dropFirst()))
        }
        if command == "replay" {
            guard let path = arguments.dropFirst().first else {
                CLIOutput.writeError("Укажите JSONL-файл для replay.\n")
                return 2
            }
            return replay(path: path)
        }
        return try await send(arguments: arguments)
    }

    private static func send(arguments: [String]) async throws -> Int32 {
        var transport = TransportKind.auto
        var session: SessionID?
        var forceNew = false
        var promptParts: [String] = []

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--transport":
                index += 1
                guard index < arguments.count,
                      let value = TransportKind(rawValue: arguments[index])
                else {
                    CLIOutput.writeError("Неизвестный транспорт.\n")
                    return 2
                }
                transport = value
            case "--session":
                index += 1
                guard index < arguments.count else {
                    CLIOutput.writeError("Укажите идентификатор сессии.\n")
                    return 2
                }
                session = arguments[index]
            case "--new":
                forceNew = true
            default:
                promptParts.append(argument)
            }
            index += 1
        }

        if forceNew {
            session = nil
        }
        let prompt = promptParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            CLIOutput.writeError("Укажите текст запроса.\n")
            return 2
        }

        signal(SIGINT, SIG_IGN)
        let manager = TransportManager(config: HermesConfig(), kind: transport)
        let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT)
        interruptSource.setEventHandler {
            Task {
                if let sid = await manager.lastSessionID {
                    await manager.interrupt(session: sid)
                }
                CLIOutput.writeError("\nПрервано.\n")
                exit(130)
            }
        }
        interruptSource.resume()
        defer { interruptSource.cancel() }

        do {
            let code = try await performSend(
                manager: manager,
                prompt: prompt,
                session: session
            )
            await manager.close()
            return code
        } catch {
            await manager.close()
            throw error
        }
    }

    private static func performSend(
        manager: TransportManager,
        prompt: String,
        session: SessionID?
    ) async throws -> Int32 {
        try await manager.connect()
        if let reason = await manager.fallbackReason {
            CLIOutput.writeError("Автовыбор транспорта: \(reason)\n")
        }
        let resolved = await manager.resolvedKind
        CLIOutput.writeError("Транспорт: \(resolved?.displayName ?? "неизвестен")\n")

        var receivedText = ""
        var finalText: String?
        for try await event in manager.send(prompt, session: session, mode: .text) {
            switch event {
            case let .sessionBound(id):
                CLIOutput.writeError("Сессия: \(id)\n")
            case let .textDelta(text):
                receivedText += text
                CLIOutput.write(text)
            case .thinkingStarted:
                CLIOutput.writeError(CLIOutput.grey("…\n"))
            case let .reasoningDelta(text):
                CLIOutput.writeError(CLIOutput.grey(text))
            case let .toolStarted(id, name, detail):
                let suffix = detail.map { ": \($0)" } ?? ""
                CLIOutput.writeError(CLIOutput.grey("[\(name) \(id)]\(suffix)\n"))
            case let .toolOutput(id, imagePath, summary):
                let parts = [imagePath, summary].compactMap(\.self)
                if !parts.isEmpty {
                    CLIOutput.writeError(CLIOutput.grey("[\(id)] \(parts.joined(separator: " · "))\n"))
                }
            case let .toolFinished(id, ok):
                CLIOutput.writeError(CLIOutput.grey("[\(ok ? "ok" : "fail") \(id)]\n"))
            case let .serverRequest(request):
                try await answer(request: request, manager: manager)
            case let .completed(text):
                finalText = text
            case .cancelled:
                CLIOutput.writeError("\nПрервано.\n")
                return 130
            case let .failed(error):
                CLIOutput.writeError("\nОшибка: \(error.localizedDescription)\n")
                return 1
            }
        }
        if receivedText.isEmpty, let finalText, !finalText.isEmpty {
            CLIOutput.write(finalText)
        }
        if !receivedText.isEmpty, !receivedText.hasSuffix("\n") {
            CLIOutput.write("\n")
        }
        return 0
    }

    private static func answer(
        request: ServerRequest,
        manager: TransportManager
    ) async throws {
        switch request.kind {
        case .approval:
            CLIOutput
                .writeError(CLIOutput
                    .grey("Запрос подтверждения: \(request.requestDescription ?? request.command ?? "")\n"))
            try await manager.respond(to: request, with: .approval(choice: "deny"))
        case .clarify:
            try await manager.respond(to: request, with: .clarify(answer: ""))
        case .other:
            try await manager.respond(to: request, with: .cancel)
        }
    }

    private static func listSessions(arguments: [String]) async throws -> Int32 {
        var transport = TransportKind.auto
        var limit = 20
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--transport":
                index += 1
                guard index < arguments.count,
                      let value = TransportKind(rawValue: arguments[index])
                else {
                    CLIOutput.writeError("Неизвестный транспорт.\n")
                    return 2
                }
                transport = value
            case "--limit":
                index += 1
                if index < arguments.count, let value = Int(arguments[index]) {
                    limit = value
                }
            default:
                break
            }
            index += 1
        }
        let manager = TransportManager(config: HermesConfig(), kind: transport)
        do {
            try await manager.connect()
            let sessions = try await manager.sessions(limit: limit)
            for session in sessions {
                let date = session.updatedAt.map(CLIOutput.formatDate) ?? "—"
                CLIOutput.write("\(session.id)\t\(date)\t\(session.source)\t\(session.title)\n")
            }
            await manager.close()
            return 0
        } catch {
            await manager.close()
            throw error
        }
    }

    private static func replay(path: String) -> Int32 {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            CLIOutput.writeError("Не удалось прочитать \(path).\n")
            return 1
        }
        for line in contents.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONValue(from: data),
                  entry["dir"]?.stringValue == "recv",
                  let frame = entry["frame"],
                  frame["method"]?.stringValue == "event"
            else { continue }
            for event in HermesEventMapper.gatewayEvent(frame["params"] ?? .null) {
                CLIOutput.write(describe(event))
            }
        }
        return 0
    }

    private static func describe(_ event: HermesEvent) -> String {
        switch event {
        case let .sessionBound(id): "session: \(id)\n"
        case .thinkingStarted: "thinking\n"
        case let .reasoningDelta(text): "reasoning: \(text)\n"
        case let .textDelta(text): "text: \(text)\n"
        case let .toolStarted(id, name, detail): "tool.start: \(name) \(id) \(detail ?? "")\n"
        case let .toolOutput(id, imagePath, summary): "tool.output: \(id) \(imagePath ?? "") \(summary ?? "")\n"
        case let .toolFinished(id, ok): "tool.done: \(id) \(ok)\n"
        case let .serverRequest(request): "request: \(request.kind) \(request.id) \(request.choices)\n"
        case let .completed(text): "completed: \(text ?? "")\n"
        case .cancelled: "cancelled\n"
        case let .failed(error): "failed: \(error.localizedDescription)\n"
        }
    }
}
