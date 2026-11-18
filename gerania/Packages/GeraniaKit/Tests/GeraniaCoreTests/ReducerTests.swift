import GeraniaCore
import Testing

@Suite("Reducer")
struct ReducerTests {
    @Test("Wake from idle starts listening and shows the panel")
    func wakeFromIdle() {
        let (state, effects) = reduce(state: .idle, action: .wake(at: 100))

        #expect(state == .listening(deadline: 108))
        #expect(effects.contains(.startListening))
        #expect(effects.contains(.showPanel))
        #expect(!effects.contains(.interrupt))
    }

    @Test("Barge-in while streaming interrupts the turn and listens again")
    func bargeInFromStreaming() {
        let (state, effects) = reduce(state: .streaming, action: .wake(at: 200))

        #expect(state == .listening(deadline: 208))
        #expect(effects.contains(.interrupt))
        #expect(effects.first == .interrupt)
    }

    @Test("Barge-in while speaking also stops the voice")
    func bargeInFromSpeaking() {
        let (state, effects) = reduce(state: .speaking, action: .wake(at: 300))

        #expect(state == .listening(deadline: 308))
        #expect(effects.contains(.stopSpeaking))
        #expect(effects.contains(.interrupt))
    }

    @Test("Submitting a prompt moves listening into thinking")
    func promptSubmitted() {
        let (state, effects) = reduce(
            state: .listening(deadline: 10),
            action: .promptSubmitted
        )

        #expect(state == .thinking(tools: []))
        #expect(effects.contains(.showPanel))
    }

    @Test("Tool lifecycle updates the chip")
    func toolLifecycle() {
        let chip = ToolChip(id: "t1", name: "terminal", detail: "date -u")
        let (thinking, _) = reduce(state: .thinking(tools: []), action: .toolStarted(chip))
        guard case let .thinking(tools) = thinking else {
            Issue.record("expected thinking state")
            return
        }
        #expect(tools == [chip])

        let (finished, _) = reduce(state: thinking, action: .toolFinished(id: "t1", ok: false))
        guard case let .thinking(doneTools) = finished else {
            Issue.record("expected thinking state")
            return
        }
        #expect(doneTools.first?.isFinished == true)
        #expect(doneTools.first?.isError == true)
    }

    @Test("Tool output is attached before the chip finishes")
    func toolOutput() {
        let chip = ToolChip(id: "t1", name: "browser_exec", detail: "screenshot")
        let (started, _) = reduce(state: .thinking(tools: []), action: .toolStarted(chip))
        let (attached, _) = reduce(
            state: started,
            action: .toolOutput(id: "t1", imagePath: "/tmp/shot.png", summary: "Страница YouTube")
        )
        guard case let .thinking(tools) = attached else {
            Issue.record("expected thinking state")
            return
        }
        #expect(tools.first?.imagePath == "/tmp/shot.png")
        #expect(tools.first?.summary == "Страница YouTube")
        #expect(tools.first?.isFinished == false)

        let (finished, _) = reduce(state: attached, action: .toolFinished(id: "t1", ok: true))
        guard case let .thinking(done) = finished else {
            Issue.record("expected thinking state")
            return
        }
        #expect(done.first?.imagePath == "/tmp/shot.png")
        #expect(done.first?.summary == "Страница YouTube")
        #expect(done.first?.isFinished == true)
    }

    @Test("Text deltas move thinking into streaming and stay there")
    func textStreaming() {
        let (streaming, _) = reduce(state: .thinking(tools: []), action: .textStarted)
        #expect(streaming == .streaming)

        let (stillStreaming, _) = reduce(state: streaming, action: .textDelta("привет"))
        #expect(stillStreaming == .streaming)
    }

    @Test("Completion finishes the turn and schedules hiding")
    func completion() {
        let (state, effects) = reduce(state: .streaming, action: .completed(finalText: "ok"))

        #expect(state == .done)
        #expect(effects.contains(.playSound(.done)))
        #expect(effects.contains(.hidePanel(after: 6)))
    }

    @Test("Cancel returns to idle and silences speech")
    func cancel() {
        let (state, effects) = reduce(state: .thinking(tools: []), action: .cancelled)

        #expect(state == .idle)
        #expect(effects.contains(.stopSpeaking))
        #expect(effects.contains(.hidePanel(after: 0)))
    }

    @Test("Stop interrupts work and resets the state")
    func stop() {
        let (state, effects) = reduce(state: .thinking(tools: []), action: .stop)

        #expect(state == .idle)
        #expect(effects.contains(.interrupt))
        #expect(effects.contains(.stopSpeaking))
        #expect(effects.contains(.cancelTranscription))
    }

    @Test("Server request awaits an answer, then returns to thinking")
    func serverRequest() {
        let request = ServerRequest(
            id: "srq-1",
            kind: .approval,
            sessionID: "local-1",
            command: "rm -rf /tmp/x",
            choices: ["once", "deny"]
        )
        let (awaiting, _) = reduce(state: .thinking(tools: []), action: .serverRequest(request))
        #expect(awaiting == .awaitingApproval(request))

        let (resumed, _) = reduce(state: awaiting, action: .serverRequestAnswered)
        #expect(resumed == .thinking(tools: []))
    }

    @Test("Listening timeout is ignored outside the listening state")
    func timeoutOutsideListening() {
        let (state, effects) = reduce(state: .streaming, action: .listenTimedOut)

        #expect(state == .streaming)
        #expect(effects.isEmpty)
    }

    @Test("Failures become an error state")
    func failure() {
        let (state, effects) = reduce(state: .thinking(tools: []), action: .failed("сеть"))

        #expect(state == .error("сеть"))
        #expect(effects.contains(.playSound(.error)))
    }

    @Test("Speech start and finish wrap the done state")
    func speechCycle() {
        let (speaking, _) = reduce(state: .done, action: .speechStarted)
        #expect(speaking == .speaking)

        let (done, _) = reduce(state: speaking, action: .speechFinished)
        #expect(done == .done)
    }

    @Test("Closing the HUD stops the running turn")
    func dismissWhileStreaming() {
        let (state, effects) = reduce(state: .streaming, action: .dismissed)

        #expect(state == .idle)
        #expect(effects.contains(.stopListening))
        #expect(effects.contains(.stopSpeaking))
        #expect(effects.contains(.interrupt))
        #expect(effects.contains(.hidePanel(after: 0)))
    }
}
