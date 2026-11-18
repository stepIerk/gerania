import Foundation

/// Source of the current time. Abstracted so the throttling can be tested deterministically.
public protocol StreamClock: Sendable {
    /// Current time in seconds since the reference date.
    var now: TimeInterval { get }
}

/// Clock backed by the system time.
public struct SystemStreamClock: StreamClock {
    public init() {}

    public var now: TimeInterval {
        Date().timeIntervalSince1970
    }
}

/// Collects streamed text and publishes snapshots at a limited rate.
///
/// Long answers arrive as hundreds of small deltas; re-rendering on every delta is far
/// too expensive, so the buffer hands out a new snapshot at most `minimumInterval`
/// seconds apart.
public struct StreamBuffer: Sendable {
    /// Minimal time between two published snapshots.
    public let minimumInterval: TimeInterval

    private let clock: any StreamClock
    private var text = ""
    private var lastPublishedAt: TimeInterval?

    public init(clock: any StreamClock = SystemStreamClock(), minimumInterval: TimeInterval = 1.0 / 30) {
        self.clock = clock
        self.minimumInterval = minimumInterval
    }

    /// Text received so far.
    public var current: String {
        text
    }

    /// Adds a delta and returns a snapshot when the throttle window has passed.
    public mutating func append(_ delta: String) -> String? {
        text += delta
        return publishIfDue()
    }

    /// Returns a snapshot regardless of the throttle window.
    public mutating func flush() -> String {
        lastPublishedAt = clock.now
        return text
    }

    /// Drops the collected text.
    public mutating func reset() {
        text = ""
        lastPublishedAt = nil
    }

    /// Returns the current text when enough time has passed since the last snapshot.
    public mutating func publishIfDue() -> String? {
        let now = clock.now
        if let lastPublishedAt, now - lastPublishedAt < minimumInterval {
            return nil
        }
        lastPublishedAt = now
        return text
    }
}
