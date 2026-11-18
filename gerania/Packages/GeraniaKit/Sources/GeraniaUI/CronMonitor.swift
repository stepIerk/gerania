import Foundation
import GeraniaCore
import HermesKit
import Observation

/// One finished plan run, ready for a banner and a HUD card.
public struct CronResult: Sendable, Equatable, Identifiable {
    public let output: CronOutput
    public let digest: CronOutputDigest

    public var id: String {
        output.id
    }

    /// Job name from the run document; the job id when the header is missing.
    public var title: String {
        digest.title ?? output.jobID
    }
}

/// Watches `cron/output` and the ticker heartbeat while Gerania runs.
///
/// Hermes delivers `--deliver local` results only as files, so without this
/// watcher a reminder fires silently. The monitor polls instead of using
/// FSEvents: one directory listing every few seconds is cheap, needs no
/// run-loop source, and also works when `output/` does not exist yet.
@MainActor
@Observable
public final class CronMonitor {
    public private(set) var scheduler: CronSchedulerStatus = .notRunning
    public nonisolated let directory: URL

    /// Called with new results, oldest first.
    @ObservationIgnored public var onResults: (([CronResult]) -> Void)?
    @ObservationIgnored private var tracker: CronResultTracker
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loop: Task<Void, Never>?

    static let watermarkKey = "cronResultsWatermark"
    static let seenKey = "cronResultsSeen"

    public init(directory: URL, defaults: UserDefaults = .standard) {
        self.directory = directory
        self.defaults = defaults
        let stamp = defaults.object(forKey: Self.watermarkKey) as? Double
        tracker = CronResultTracker(
            watermark: stamp.map { Date(timeIntervalSince1970: $0) },
            seenIDs: defaults.stringArray(forKey: Self.seenKey) ?? []
        )
    }

    public func start(every interval: Duration = .seconds(10)) {
        guard loop == nil else { return }
        Log.ui.info("cron monitor started: \(self.directory.path, privacy: .public)")
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.poll()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// One check: the heartbeat and the new result files. Public for the tests.
    @discardableResult
    public func poll(now: Date = Date()) -> [CronResult] {
        scheduler = CronSchedulerStatus.read(cronDirectory: directory, now: now)
        let outputs = CronOutputStore.recent(in: directory, limit: 50)
        let fresh = tracker.takeNew(from: outputs, now: now)
        save()
        guard !fresh.isEmpty else { return [] }
        let results = fresh.map { output in
            let text = (try? CronOutputStore.read(output)) ?? ""
            return CronResult(output: output, digest: CronOutputDigest.parse(text))
        }
        Log.ui.info("cron results: \(results.count, privacy: .public) new")
        onResults?(results)
        return results
    }

    private func save() {
        if let watermark = tracker.watermark {
            defaults.set(watermark.timeIntervalSince1970, forKey: Self.watermarkKey)
        }
        defaults.set(tracker.seenIDs, forKey: Self.seenKey)
    }
}
