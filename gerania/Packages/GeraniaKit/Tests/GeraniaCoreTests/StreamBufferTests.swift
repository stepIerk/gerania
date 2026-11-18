import Foundation
import GeraniaCore
import Testing

/// Deterministic clock for the throttling tests.
private final class TestClock: StreamClock, @unchecked Sendable {
    var now: TimeInterval = 0

    func advance(_ delta: TimeInterval) {
        now += delta
    }
}

@Suite("StreamBuffer")
struct StreamBufferTests {
    @Test("The first delta is published immediately")
    func firstDeltaIsPublished() {
        let clock = TestClock()
        var buffer = StreamBuffer(clock: clock)

        #expect(buffer.append("Привет") == "Привет")
    }

    @Test("Deltas inside the throttle window are not published")
    func throttledDeltas() {
        let clock = TestClock()
        var buffer = StreamBuffer(clock: clock)

        #expect(buffer.append("a") == "a")
        #expect(buffer.append("b") == nil)
        #expect(buffer.append("c") == nil)
        #expect(buffer.current == "abc")
    }

    @Test("A snapshot is published after the throttle window")
    func publishesAfterInterval() {
        let clock = TestClock()
        var buffer = StreamBuffer(clock: clock)

        #expect(buffer.append("a") == "a")
        clock.advance(0.04)
        #expect(buffer.append("b") == "ab")
    }

    @Test("No more than thirty snapshots per second")
    func rateLimit() {
        let clock = TestClock()
        var buffer = StreamBuffer(clock: clock)
        var published = 0

        for index in 0 ..< 1000 {
            clock.advance(0.001)
            if buffer.append("x") != nil {
                published += 1
            }
        }

        #expect(published <= 31)
        #expect(published >= 29)
    }

    @Test("Flush returns the whole text regardless of the window")
    func flush() {
        let clock = TestClock()
        var buffer = StreamBuffer(clock: clock)

        #expect(buffer.append("a") == "a")
        #expect(buffer.append("b") == nil)
        #expect(buffer.flush() == "ab")
    }

    @Test("Reset drops the collected text")
    func reset() {
        let clock = TestClock()
        var buffer = StreamBuffer(clock: clock)

        _ = buffer.append("a")
        buffer.reset()

        #expect(buffer.current.isEmpty)
        #expect(buffer.append("b") == "b")
    }
}
