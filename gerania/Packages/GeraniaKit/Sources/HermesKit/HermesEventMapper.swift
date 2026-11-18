import Foundation
import GeraniaCore

public enum HermesEventMapper {
    public static func gatewayEvent(_ params: JSONValue) -> [HermesEvent] {
        guard let type = params["type"]?.stringValue else { return [] }
        let payload = params["payload"] ?? .object([:])

        switch type {
        case "message.delta":
            guard let text = payload["text"]?.stringValue, !text.isEmpty else { return [] }
            return [.textDelta(text)]
        case "reasoning.delta", "thinking.delta":
            guard let text = payload["text"]?.stringValue, !text.isEmpty else { return [] }
            return [.reasoningDelta(text)]
        case "tool.start":
            let id = payload["tool_id"]?.stringValue
                ?? payload["tool_call_id"]?.stringValue
                ?? UUID().uuidString
            let name = payload["name"]?.stringValue
                ?? payload["tool_name"]?.stringValue
                ?? "tool"
            let detail = ToolDetail.text(
                name: name,
                args: payload["args"],
                context: payload["context"]?.stringValue
            )
            return [.toolStarted(id: id, name: name, detail: detail)]
        case "tool.complete":
            let id = payload["tool_id"]?.stringValue
                ?? payload["tool_call_id"]?.stringValue
                ?? ""
            let name = payload["name"]?.stringValue
                ?? payload["tool_name"]?.stringValue
                ?? ""
            let ok = payload["is_error"]?.boolValue.map { !$0 } ?? true
            let imagePath = payload["image_path"]?.stringValue
                .flatMap { $0.isEmpty ? nil : $0 }
            let summary = ToolResultSummary.text(name: name, result: payload["result"])
            var events: [HermesEvent] = []
            if imagePath != nil || summary != nil {
                events.append(.toolOutput(id: id, imagePath: imagePath, summary: summary))
            }
            events.append(.toolFinished(id: id, ok: ok))
            return events
        case "message.complete":
            let text = payload["text"]?.stringValue
            let status = payload["status"]?.stringValue
            let outcome = payload["outcome"]?.stringValue
            if status == "interrupted" || outcome == "cancelled" {
                return [.cancelled]
            }
            return [.completed(finalText: text)]
        case "error":
            let message = payload["message"]?.stringValue
                ?? payload["error"]?.stringValue
                ?? "unknown error"
            return [.failed(.protocolError(message))]
        case "approval.request", "clarify.request":
            return gatewayPrompt(type: type, params: params).map { [.serverRequest($0)] } ?? []
        default:
            return []
        }
    }

    public static func gatewayPrompt(type: String, params: JSONValue) -> ServerRequest? {
        let payload = params["payload"] ?? .object([:])
        guard let promptID = payload["prompt_id"]?.stringValue else { return nil }
        let kind: ServerRequest.Kind = type == "clarify.request" ? .clarify : .approval
        let question = payload["question"]?.stringValue ?? payload["description"]?.stringValue
        return ServerRequest(
            id: promptID,
            kind: kind,
            sessionID: params["session_id"]?.stringValue,
            command: payload["command"]?.stringValue,
            requestDescription: question,
            choices: payload["choices"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            executionGeneration: payload["execution_generation"]?.intValue
                ?? params["execution_generation"]?.intValue,
            admissionID: params["admission_id"]?.stringValue
        )
    }

    public static func gatewayServerRequest(
        id: JSONValue,
        method: String,
        params: JSONValue
    ) -> ServerRequest? {
        let kind: ServerRequest.Kind
        switch method {
        case "approval": kind = .approval
        case "clarify": kind = .clarify
        default: return nil
        }
        let promptID = params["prompt_id"]?.stringValue ?? id.stringValue ?? "\(id.intValue ?? 0)"
        return ServerRequest(
            id: promptID,
            kind: kind,
            sessionID: params["session_id"]?.stringValue,
            command: params["command"]?.stringValue,
            requestDescription: params["question"]?.stringValue
                ?? params["description"]?.stringValue,
            choices: params["choices"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            executionGeneration: params["execution_generation"]?.intValue,
            admissionID: params["admission_id"]?.stringValue
        )
    }

    public static func acpUpdate(_ params: JSONValue) -> [HermesEvent] {
        guard let update = params["update"], let kind = update["sessionUpdate"]?.stringValue else { return [] }

        switch kind {
        case "agent_message_chunk":
            guard let text = contentText(update["content"]), !text.isEmpty else { return [] }
            return [.textDelta(text)]
        case "agent_thought_chunk":
            guard let text = contentText(update["content"]), !text.isEmpty else { return [] }
            return [.reasoningDelta(text)]
        case "tool_call":
            let id = update["toolCallId"]?.stringValue ?? UUID().uuidString
            let name = update["title"]?.stringValue
                ?? update["kind"]?.stringValue
                ?? "tool"
            let detail = ToolDetail.text(name: name, args: update["rawInput"], context: nil)
            return [.toolStarted(id: id, name: name, detail: detail)]
        case "tool_call_update":
            let id = update["toolCallId"]?.stringValue ?? ""
            let status = update["status"]?.stringValue
            let ok = status != "failed" && status != "cancelled"
            return [.toolFinished(id: id, ok: ok)]
        default:
            return []
        }
    }

    public static func acpPermissionRequest(
        id: JSONValue,
        params: JSONValue
    ) -> ServerRequest? {
        let toolCall = params["toolCall"] ?? .object([:])
        let options = params["options"]?.arrayValue ?? []
        let choices = options.compactMap { option -> String? in
            option["optionId"]?.stringValue ?? option["name"]?.stringValue
        }
        return ServerRequest(
            id: id.stringValue ?? "\(id.intValue ?? 0)",
            kind: .approval,
            sessionID: params["sessionId"]?.stringValue,
            command: toolCall["rawInput"]?["command"]?.stringValue,
            requestDescription: toolCall["title"]?.stringValue,
            choices: choices
        )
    }

    private static func contentText(_ content: JSONValue?) -> String? {
        guard let content else { return nil }
        if let text = content.stringValue {
            return text
        }
        if let text = content["text"]?.stringValue {
            return text
        }
        if let items = content.arrayValue {
            return items.compactMap { contentText($0) }.joined()
        }
        return nil
    }
}
