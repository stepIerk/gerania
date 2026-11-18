import Foundation
import GeraniaCore
import HermesKit
import RealtimeKit
@preconcurrency import UserNotifications

/// Tool calls and Hermes tasks of the live dialog.
extension AppModel {
    func handleLiveToolCalls(_ calls: [LiveToolCall]) {
        for call in calls {
            switch call.name {
            case "run_task":
                runLiveTask(call)
            case "get_tasks":
                respondLiveTool(call, response: ["tasks": .array(liveTasks.snapshots.map(\.json))])
            case "steer_task":
                steerLiveTask(call)
            case "cancel_task":
                cancelLiveTask(call)
            case "cancel_all_tasks":
                liveTasks.cancelAll()
                respondLiveTool(call, response: ["status": "cancelled"])
            case "get_task_result":
                taskResult(call)
            case "respond_approval":
                respondLiveApproval(call)
            case "finish_conversation":
                respondLiveTool(call, response: ["status": "closing"])
                requestLiveEnd(reason: "Диалог завершён")
            default:
                respondLiveTool(call, response: ["error": "неизвестный инструмент"])
            }
        }
    }

    private func runLiveTask(_ call: LiveToolCall) {
        guard let goal = call.arguments["goal"]?.stringValue,
              !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            respondLiveTool(call, response: ["error": "не указана цель задачи"])
            return
        }
        let title = call.arguments["title"]?.stringValue
        let snapshot = liveTasks.start(goal: goal, title: title)
        respondLiveTool(call, response: snapshot.json)
    }

    private func steerLiveTask(_ call: LiveToolCall) {
        guard let id = call.arguments["task_id"]?.stringValue,
              let instruction = call.arguments["instruction"]?.stringValue
        else {
            respondLiveTool(call, response: ["error": "нужны task_id и instruction"])
            return
        }
        let ok = liveTasks.steer(id: id, instruction: instruction)
        respondLiveTool(call, response: [
            "ok": .bool(ok),
            "task_id": .string(id),
        ])
    }

    private func cancelLiveTask(_ call: LiveToolCall) {
        guard let id = call.arguments["task_id"]?.stringValue else {
            respondLiveTool(call, response: ["error": "нужен task_id"])
            return
        }
        liveTasks.cancel(id: id)
        respondLiveTool(call, response: ["task_id": .string(id), "status": "cancelled"])
    }

    private func taskResult(_ call: LiveToolCall) {
        guard let id = call.arguments["task_id"]?.stringValue,
              let snapshot = liveTasks.snapshot(id: id)
        else {
            respondLiveTool(call, response: ["error": "задача не найдена"])
            return
        }
        respondLiveTool(call, response: snapshot.json)
    }

    private func respondLiveApproval(_ call: LiveToolCall) {
        guard let requestID = call.arguments["request_id"]?.stringValue else {
            respondLiveTool(call, response: ["error": "нужен request_id"])
            return
        }
        let decision = call.arguments["decision"]?.stringValue
        let answer = call.arguments["answer"]?.stringValue
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.liveTasks.respondApproval(
                    requestID: requestID,
                    decision: decision,
                    answer: answer
                )
                self.respondLiveTool(call, response: ["ok": .bool(true)])
            } catch {
                self.respondLiveTool(call, response: ["error": .string(error.localizedDescription)])
            }
        }
    }

    private func respondLiveTool(
        _ call: LiveToolCall,
        response: [String: JSONValue],
        scheduling: LiveToolScheduling? = .whenIdle
    ) {
        respondLiveTool(call, response: .object(response), scheduling: scheduling)
    }

    private func respondLiveTool(
        _ call: LiveToolCall,
        response: JSONValue,
        scheduling: LiveToolScheduling? = .whenIdle
    ) {
        guard let conversation = liveConversation else {
            return
        }
        let effective = settings.liveModel.contains("extended-thinking") ? nil : scheduling
        Task {
            try? await conversation.sendToolResponse(
                callID: call.id,
                name: call.name,
                response: response,
                scheduling: effective
            )
        }
    }

    var liveTasks: LiveTaskManager {
        if let liveTaskManager {
            return liveTaskManager
        }
        let manager = LiveTaskManager { [weak self] in
            guard let self else {
                throw HermesError.notConfigured("приложение закрывается")
            }
            return TransportManager(
                config: self.makeConfig(self.primaryCandidate),
                kind: self.settings.transport
            )
        }
        manager.onChange = { [weak self] snapshot in
            self?.handleLiveTaskChange(snapshot)
        }
        manager.onFinished = { [weak self] snapshot in
            self?.announceLiveTask(snapshot)
        }
        manager.onApproval = { [weak self] snapshot, request in
            self?.handleLiveTaskApproval(snapshot, request: request)
        }
        manager.onApprovalExpired = { [weak self] snapshot in
            self?.handleLiveApprovalExpired(snapshot)
        }
        liveTaskManager = manager
        return manager
    }

    private func handleLiveTaskChange(_ snapshot: LiveTaskSnapshot) {
        let chip = ToolChip(
            id: snapshot.id,
            name: snapshot.title,
            detail: snapshot.status.displayName,
            isFinished: snapshot.status.isTerminal,
            isError: snapshot.status == .failed
        )
        hud.startTool(chip)
    }

    private func announceLiveTask(_ snapshot: LiveTaskSnapshot) {
        let status = switch snapshot.status {
        case .completed: "завершена"
        case .failed: "завершилась ошибкой"
        case .cancelled: "отменена"
        case .queued, .running: "ещё выполняется"
        }
        let result = snapshot.summary.map { String($0.prefix(1500)) } ?? ""
        if isLiveActive, liveConversation != nil {
            let note = """
            [СИСТЕМА] Задача «\(snapshot.title)» \(status).
            Результат: \(result.isEmpty ? "пусто" : result)
            Сообщи пользователю кратко, что задача \(status), и назови главное из результата.
            """
            sendLiveNote(note)
            return
        }
        if settings.speakAnswers {
            speaker?.speakNow("Задача «\(snapshot.title)» \(status)")
        }
        notifyTask(snapshot, status: status)
    }

    private func handleLiveTaskApproval(_ snapshot: LiveTaskSnapshot, request: ServerRequest) {
        if isLiveActive, liveConversation != nil {
            let choices = request.choices.joined(separator: ", ")
            let note = if request.kind == .clarify {
                """
                [СИСТЕМА] Задача «\(snapshot.title)» просит уточнение.
                Вопрос: \(request.requestDescription ?? request.command ?? "уточнение")
                Идентификатор: \(request.id)
                Спроси пользователя и вызови respond_approval с request_id и answer.
                """
            } else {
                """
                [СИСТЕМА] Задача «\(snapshot.title)» просит подтверждение.
                Запрос: \(request.requestDescription ?? request.command ?? "действие")
                Идентификатор: \(request.id)
                Варианты: \(choices.isEmpty ? "once, always, deny" : choices)
                Спроси пользователя и вызови respond_approval с request_id и decision.
                """
            }
            sendLiveNote(note)
        } else {
            hud.approval = request
            notifyTask(snapshot, status: "просит подтверждение")
        }
    }

    private func handleLiveApprovalExpired(_ snapshot: LiveTaskSnapshot) {
        if isLiveActive, liveConversation != nil {
            sendLiveNote("""
            [СИСТЕМА] Задача «\(snapshot.title)»: пользователь не ответил на запрос
            подтверждения, действие отклонено. Сообщи об этом коротко.
            """)
        } else {
            hud.hint = "Подтверждение для задачи «\(snapshot.title)» отклонено по таймауту"
        }
    }

    private func sendLiveNote(_ note: String) {
        guard isLiveActive, liveConversation != nil else {
            return
        }
        if case .speaking = state {
            liveNoteQueue.append(note)
            return
        }
        if case .streaming = state {
            liveNoteQueue.append(note)
            return
        }
        guard let conversation = liveConversation else { return }
        Task { try? await conversation.sendText(note) }
    }

    func flushLiveNotes() {
        guard isLiveActive, let conversation = liveConversation else {
            liveNoteQueue.removeAll()
            return
        }
        guard !liveNoteQueue.isEmpty else {
            return
        }
        let note = liveNoteQueue.joined(separator: "\n\n")
        liveNoteQueue.removeAll()
        Task { try? await conversation.sendText(note) }
    }

    private func notifyTask(_ snapshot: LiveTaskSnapshot, status: String) {
        guard settings.notifications else {
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Задача «\(snapshot.title)» \(status)"
            content.body = snapshot.summary.map { String($0.prefix(300)) } ?? ""
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: snapshot.id,
                content: content,
                trigger: nil
            ))
        }
    }
}
