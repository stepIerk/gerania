import Foundation
import GeraniaCore
import HermesKit
import Testing

@Suite("Hermes protocol fixtures")
struct FixtureMappingTests {
    @Test("Simple turn maps deltas and completion")
    func simpleTurn() throws {
        let events = try fixtureEvents("gateway-simple.jsonl")

        #expect(events.contains(.textDelta("OK")))
        #expect(events.contains(.completed(finalText: "OK")))
        #expect(events.contains { event in
            if case .reasoningDelta = event {
                return true
            }
            return false
        })
    }

    @Test("Markdown turn preserves the final text")
    func markdownTurn() throws {
        let events = try fixtureEvents("gateway-markdown.jsonl")
        let text = events.compactMap { event -> String? in
            if case let .textDelta(value) = event {
                return value
            }
            return nil
        }.joined()

        #expect(text.contains("| Термин | Значение |"))
        #expect(text.contains("```python"))
        #expect(events.contains { event in
            if case let .completed(final) = event {
                return final?.contains("print(\"OK\")") == true
            }
            return false
        })
    }

    @Test("Tool events map to started and finished")
    func toolTurn() throws {
        let events = try fixtureEvents("gateway-tool.jsonl")

        #expect(events.contains(.toolStarted(
            id: "call_f4e7555957f1",
            name: "terminal",
            detail: "date -u +%FT%TZ"
        )))
        #expect(events.contains(.toolOutput(
            id: "call_f4e7555957f1",
            imagePath: nil,
            summary: "2026-11-10T13:00:12Z"
        )))
        #expect(events.contains(.toolFinished(id: "call_f4e7555957f1", ok: true)))
        #expect(events.contains(.completed(finalText: "2026-11-10T13:00:12Z")))
    }

    @Test("tool.complete carries the screenshot and the short result")
    func toolOutput() {
        let params: JSONValue = [
            "type": "tool.complete",
            "payload": [
                "tool_id": "c1",
                "name": "web_search",
                "is_error": false,
                "image_path": "/tmp/shot.png",
                "result": .string(
                    #"{"success": true, "data": {"web": [{"title": "Swift", "url": "https://swift.org"}]}}"#
                ),
            ],
        ]

        let events = HermesEventMapper.gatewayEvent(params)

        #expect(events == [
            .toolOutput(id: "c1", imagePath: "/tmp/shot.png", summary: "1 результат · Swift"),
            .toolFinished(id: "c1", ok: true),
        ])
    }

    @Test("tool.complete without output emits only the finish")
    func plainToolFinish() {
        let params: JSONValue = [
            "type": "tool.complete",
            "payload": [
                "tool_id": "c2",
                "name": "custom_tool",
                "is_error": false,
                "result": .string(#"{"ok": true}"#),
            ],
        ]

        let events = HermesEventMapper.gatewayEvent(params)

        #expect(events == [.toolFinished(id: "c2", ok: true)])
    }

    @Test("Interrupted turn maps to cancelled")
    func interruptTurn() throws {
        let events = try fixtureEvents("gateway-interrupt.jsonl")

        #expect(events.contains(.cancelled))
        #expect(!events.contains { event in
            if case .completed = event {
                return true
            }
            return false
        })
    }

    @Test("Approval request carries prompt identity and choices")
    func approvalTurn() throws {
        let events = try fixtureEvents("gateway-approval.jsonl")
        let request = try #require(events.compactMap { event -> ServerRequest? in
            if case let .serverRequest(request) = event {
                return request
            }
            return nil
        }.first)

        #expect(request.id == "09baa04d26914c7ebfaeb52c85df91c8")
        #expect(request.kind == .approval)
        #expect(request.choices == ["once", "deny"])
        #expect(request.executionGeneration == 1)
        #expect(request.command?.contains("curl") == true)
        #expect(request.requestDescription == "pipe remote content to shell")
    }

    @Test("Handshake has no conversation events")
    func handshake() throws {
        #expect(try fixtureEvents("gateway-handshake.jsonl").isEmpty)
    }

    private func fixtureEvents(_ name: String) throws -> [HermesEvent] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/protocol-samples/\(name)")
        let contents = try String(contentsOf: url, encoding: .utf8)
        var events: [HermesEvent] = []
        for line in contents.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONValue(from: data),
                  entry["dir"]?.stringValue == "recv",
                  let frame = entry["frame"],
                  frame["method"]?.stringValue == "event"
            else { continue }
            events += HermesEventMapper.gatewayEvent(frame["params"] ?? .null)
        }
        return events
    }
}
