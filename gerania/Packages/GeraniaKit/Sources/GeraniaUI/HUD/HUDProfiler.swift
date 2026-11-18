import Foundation
import os

/// Signpost instrumentation of the HUD update loop.
///
/// The intervals show up in Instruments (`os_signpost` category `hud`) and the duration
/// of the last update is written to the log, so the smoke test can check the budget.
@MainActor
public enum HUDProfiler {
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yourname.Gerania",
        category: "hud"
    )

    /// Duration of the last measured update in milliseconds.
    public private(set) static var lastDuration: Double = 0

    /// Runs the block inside a signpost interval and remembers how long it took.
    public static func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
        let start = DispatchTime.now()
        let state = signposter.beginInterval(name)
        defer {
            signposter.endInterval(name, state)
            let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            lastDuration = Double(elapsed) / 1_000_000
        }
        return body()
    }
}
