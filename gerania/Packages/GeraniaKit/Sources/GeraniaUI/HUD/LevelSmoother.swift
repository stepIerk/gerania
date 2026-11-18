import Foundation

/// Smooths the raw microphone level.
///
/// The attack is fast so the waveform reacts immediately, the release is slow so the
/// bars do not flicker between the syllables.
public struct LevelSmoother: Sendable {
    /// How quickly the level grows.
    public var attack: Float = 0.6
    /// How quickly the level falls.
    public var release: Float = 0.15

    private var value: Float = 0

    public init() {}

    /// Current smoothed level.
    public var level: Float {
        value
    }

    /// Updates the level with a new sample.
    public mutating func update(_ target: Float) {
        let clamped = min(max(target, 0), 1)
        let coefficient = clamped > value ? attack : release
        value += (clamped - value) * coefficient
    }

    /// Resets the smoother.
    public mutating func reset() {
        value = 0
    }
}
