import Darwin
import Foundation
import GeraniaCore
@testable import HermesKit
import Testing

@Suite("HermesKit transports")
struct TransportTests {
    @Test("JSON-RPC correlates out-of-order responses")
    func jsonRPCCorrelation() async throws {
        let recorder = FrameRecorder()
        let connection = JSONRPCConnection(send: { frame in
            await recorder.record(frame)
        })
        let first = Task { try await connection.call("first", timeout: .seconds(2)) }
        let second = Task { try await connection.call("second", timeout: .seconds(2)) }

        #expect(await waitUntil { await recorder.count == 2 })
        await connection.handle(["jsonrpc": "2.0", "id": 1, "result": "second"])
        await connection.handle(["jsonrpc": "2.0", "id": 0, "result": "first"])

        #expect(try await first.value == .string("first"))
        #expect(try await second.value == .string("second"))
    }

    @Test("JSON-RPC times out pending calls")
    func jsonRPCTimeout() async throws {
        let connection = JSONRPCConnection(send: { _ in })
        do {
            _ = try await connection.call("slow", timeout: .milliseconds(60))
            Issue.record("call unexpectedly succeeded")
        } catch let error as JSONRPCError {
            #expect(error.code == -32000)
            #expect(error.message.contains("slow"))
        }
    }

    @Test("JSON-RPC fails pending calls on disconnect")
    func jsonRPCDisconnect() async throws {
        let connection = JSONRPCConnection(send: { _ in })
        let task = Task { try await connection.call("pending", timeout: .seconds(5)) }
        try await Task.sleep(for: .milliseconds(30))

        await connection.failAll(.disconnected("test"))
        do {
            _ = try await task.value
            Issue.record("call unexpectedly succeeded")
        } catch let error as JSONRPCError {
            #expect(error.code == -32001)
        }
    }

    @Test("Unknown server requests get method-not-found")
    func unknownServerRequest() async throws {
        let recorder = FrameRecorder()
        let connection = JSONRPCConnection(send: { frame in
            await recorder.record(frame)
        })

        await connection.handle([
            "jsonrpc": "2.0",
            "id": 99,
            "method": "unknown/method",
            "params": [:],
        ])
        #expect(await waitUntil { await recorder.count == 1 })
        let frame = try #require(await recorder.last)
        #expect(frame["error"]?["code"]?.intValue == -32601)
    }

    @Test("Auto transport falls back to one-shot", .timeLimit(.minutes(1)))
    func autoFallback() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("hermes")
        try "#!/bin/sh\nexit 1\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )

        let config = HermesConfig(
            hermesPath: script.path,
            workdir: directory.path,
            homeDirectory: directory.path
        )
        let manager = TransportManager(config: config, kind: .auto)
        try await manager.connect()

        #expect(await manager.resolvedKind == .oneshot)
        #expect(await manager.fallbackReason?.contains("Gateway") == true)
        #expect(await manager.fallbackReason?.contains("ACP") == true)
        await manager.close()
    }

    @Test("One-shot cancel kills the whole process group", .timeLimit(.minutes(1)))
    func oneShotCancel() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pids")
        let script = "/bin/sleep 60 & echo \"$$ $!\" > '\(pidFile.path)'; wait"
        let config = HermesConfig(
            hermesPath: "/bin/sh",
            workdir: directory.path,
            homeDirectory: directory.path
        )
        let transport = OneShotTransport(config: config) { _, _ in
            (URL(fileURLWithPath: "/bin/sh"), ["-c", script])
        }

        let stream = transport.send("sleep", session: nil, mode: .text)
        let collector = EventCollector()
        let consumer = Task {
            do {
                for try await event in stream {
                    await collector.add(event)
                }
            } catch {
                await collector.add(.failed(.protocolError(error.localizedDescription)))
            }
        }
        guard let pids = await waitForPIDs(pidFile) else {
            await Issue.record("no pids; events: \(collector.all())")
            await transport.interrupt(session: "oneshot")
            _ = await consumer.value
            await transport.close()
            return
        }
        let group = getpgid(pids.child)
        #expect(group == pids.shell)

        await transport.interrupt(session: "oneshot")
        _ = await consumer.value
        #expect(await waitUntil { Darwin.kill(pids.child, 0) == -1 })
        #expect(await waitUntil { Darwin.kill(pids.shell, 0) == -1 })
        await transport.close()
    }

    private func waitForPIDs(_ url: URL) async -> (shell: pid_t, child: pid_t)? {
        for _ in 0 ..< 100 {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let parts = text.split(whereSeparator: \.isWhitespace)
                if parts.count == 2,
                   let shell = pid_t(parts[0]),
                   let child = pid_t(parts[1])
                {
                    return (shell, child)
                }
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return nil
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        _ predicate: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await predicate() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await predicate()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gerania-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor EventCollector {
    private var events: [HermesEvent] = []

    func add(_ event: HermesEvent) {
        events.append(event)
    }

    func all() -> [HermesEvent] {
        events
    }
}

private actor FrameRecorder {
    private var frames: [JSONValue] = []

    var count: Int {
        frames.count
    }

    var last: JSONValue? {
        frames.last
    }

    func record(_ frame: JSONValue) {
        frames.append(frame)
    }
}
