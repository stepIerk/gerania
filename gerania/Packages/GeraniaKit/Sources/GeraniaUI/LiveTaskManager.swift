import Foundation
import GeraniaCore
import HermesKit

private typealias Record = LiveTaskRecord

/// Runs up to three Hermes tasks in parallel for the live dialog.
@MainActor
final class LiveTaskManager {
    var onChange: ((LiveTaskSnapshot) -> Void)?
    var onFinished: ((LiveTaskSnapshot) -> Void)?
    var onApproval: ((LiveTaskSnapshot, ServerRequest) -> Void)?
    var onApprovalExpired: ((LiveTaskSnapshot) -> Void)?

    private let maxParallel: Int
    private let factory: @MainActor () async throws -> TransportManager
    private var records: [String: Record] = [:]
    private var order: [String] = []
    private var runningCount = 0
    private var nextNumber = 1

    init(
        maxParallel: Int = 3,
        factory: @escaping @MainActor () async throws -> TransportManager
    ) {
        self.maxParallel = max(1, maxParallel)
        self.factory = factory
    }

    /// Starts a task or puts it into the queue.
    @discardableResult
    func start(goal: String, title: String?) -> LiveTaskSnapshot {
        let id = "task-\(nextNumber)"
        nextNumber += 1
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let record = Record(
            id: id,
            title: name.isEmpty ? LiveTaskRecord.defaultTitle(for: goal) : name,
            goal: goal
        )
        records[id] = record
        order.append(id)
        publish(record)
        schedule()
        return snapshot(record)
    }

    /// All tasks, oldest first.
    var snapshots: [LiveTaskSnapshot] {
        order.compactMap { records[$0] }.map(snapshot)
    }

    /// One task.
    func snapshot(id: String) -> LiveTaskSnapshot? {
        records[id].map(snapshot)
    }

    /// Adds an instruction to a running task.
    @discardableResult
    func steer(id: String, instruction: String) -> Bool {
        guard let record = records[id], !record.status.isTerminal else {
            return false
        }
        record.pendingInstruction = instruction
        if record.status == .queued {
            record.summary = "Уточнение добавлено к задаче"
            publish(record)
        }
        return true
    }

    /// Stops one task.
    func cancel(id: String) {
        guard let record = records[id], !record.status.isTerminal else {
            return
        }
        let wasRunning = record.status == .running
        record.status = .cancelled
        record.summary = "Задача отменена"
        record.task?.cancel()
        record.task = nil
        record.approval = nil
        record.approvalTask?.cancel()
        record.approvalTask = nil
        if wasRunning {
            runningCount = max(0, runningCount - 1)
        }
        if let manager = record.manager, let session = record.session {
            Task {
                await manager.interrupt(session: session)
                await manager.close()
            }
        }
        record.manager = nil
        publish(record)
        onFinished?(snapshot(record))
        schedule()
    }

    /// Stops every task.
    func cancelAll() {
        for id in order {
            cancel(id: id)
        }
    }

    /// Answers a pending approval or clarification of the task.
    func respondApproval(
        requestID: String,
        decision: String? = nil,
        answer: String? = nil
    ) async throws -> LiveTaskSnapshot? {
        guard let record = records.values.first(where: { $0.approval?.id == requestID }),
              let request = record.approval,
              let manager = record.manager
        else {
            throw LiveTaskError.unknownRequest(requestID)
        }
        let selected: ServerRequestAnswer
        switch request.kind {
        case .clarify:
            let text = (answer ?? decision)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                throw LiveTaskError.invalidRequest("нужен answer для уточнения")
            }
            selected = .clarify(answer: text)
        case .approval, .other:
            guard let decision, let choice = Self.approvalChoice(decision) else {
                throw LiveTaskError.invalidRequest("decision должен быть once, always или deny")
            }
            selected = .approval(choice: choice)
        }
        try await manager.respond(to: request, with: selected)
        record.approval = nil
        record.approvalTask?.cancel()
        record.approvalTask = nil
        return snapshot(record)
    }

    private func schedule() {
        while runningCount < maxParallel {
            guard let record = order
                .compactMap({ records[$0] })
                .first(where: { $0.status == .queued })
            else {
                return
            }
            record.status = .running
            runningCount += 1
            publish(record)
            record.task = Task { [weak self] in
                await self?.run(record)
            }
        }
    }

    private func run(_ record: Record) async {
        do {
            let manager = try await factory()
            record.manager = manager
            try await manager.connect()
            let session = try await manager.newSession(title: record.title)
            guard !Task.isCancelled else {
                throw CancellationError()
            }
            record.session = session
            publish(record)

            var prompt = record.goal
            var text = ""
            while true {
                text = ""
                for try await event in manager.send(prompt, session: session, mode: .voice) {
                    if Task.isCancelled {
                        throw CancellationError()
                    }
                    switch event {
                    case let .textDelta(delta):
                        text += delta
                    case let .completed(finalText):
                        if let finalText, !finalText.isEmpty {
                            text = finalText
                        }
                    case let .serverRequest(request):
                        record.approval = request
                        startApprovalTimeout(record, request: request)
                        onApproval?(snapshot(record), request)
                    case let .failed(error):
                        throw error
                    case .cancelled:
                        throw CancellationError()
                    default:
                        break
                    }
                }
                if let instruction = record.takeInstruction() {
                    prompt = instruction
                    record.summary = "Выполняю уточнение"
                    publish(record)
                    continue
                }
                break
            }
            await manager.close()
            finish(record, status: .completed, summary: text)
        } catch is CancellationError {
            finish(record, status: .cancelled, summary: "Задача отменена")
        } catch {
            finish(record, status: .failed, summary: error.localizedDescription)
        }
    }

    private func finish(_ record: Record, status: LiveTaskSnapshot.Status, summary: String) {
        guard !record.status.isTerminal else {
            return
        }
        record.status = status
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        record.summary = trimmed.isEmpty ? nil : String(trimmed.prefix(4000))
        record.task = nil
        record.approval = nil
        record.approvalTask?.cancel()
        record.approvalTask = nil
        if let manager = record.manager {
            record.manager = nil
            Task { await manager.close() }
        }
        runningCount = max(0, runningCount - 1)
        publish(record)
        onFinished?(snapshot(record))
        schedule()
    }

    private func startApprovalTimeout(_ record: Record, request: ServerRequest) {
        record.approvalTask?.cancel()
        let recordID = record.id
        let requestID = request.id
        record.approvalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard !Task.isCancelled else {
                return
            }
            await self?.expireApproval(recordID: recordID, requestID: requestID)
        }
    }
}

extension LiveTaskManager {
    private func expireApproval(recordID: String, requestID: String) async {
        guard let record = records[recordID],
              let request = record.approval,
              request.id == requestID,
              let manager = record.manager
        else {
            return
        }
        record.approval = nil
        record.approvalTask = nil
        let answer: ServerRequestAnswer = request.kind == .clarify
            ? .cancel
            : .approval(choice: "deny")
        try? await manager.respond(to: request, with: answer)
        guard !record.status.isTerminal else {
            return
        }
        record.summary = "Подтверждение не получено — отклонено"
        publish(record)
        onApprovalExpired?(snapshot(record))
    }

    private func publish(_ record: Record) {
        onChange?(snapshot(record))
    }

    private func snapshot(_ record: Record) -> LiveTaskSnapshot {
        LiveTaskSnapshot(
            id: record.id,
            title: record.title,
            goal: record.goal,
            status: record.status,
            summary: record.summary,
            sessionID: record.session
        )
    }

    private static func approvalChoice(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "allow", "once", "разрешить":
            "once"
        case "always", "всегда":
            "always"
        case "deny", "отклонить":
            "deny"
        default:
            nil
        }
    }
}
