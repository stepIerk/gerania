import Foundation

/// Decides which cron results are new, so each one is announced exactly once.
///
/// State is a watermark (newest modification date already handled) plus the
/// ids of recently handled files, for files that share the watermark second.
/// The first call has no watermark: everything already on disk becomes the
/// baseline and nothing is announced, so installing Gerania next to an old
/// Hermes does not flood the person with last month's briefs. Results written
/// while the app was closed are newer than the stored watermark and are
/// announced on the next launch.
public struct CronResultTracker: Sendable, Equatable {
    public private(set) var watermark: Date?
    public private(set) var seenIDs: [String]

    /// How many handled ids to remember; older ones are below the watermark anyway.
    public static let memory = 100

    public init(watermark: Date? = nil, seenIDs: [String] = []) {
        self.watermark = watermark
        self.seenIDs = seenIDs
    }

    /// New results, oldest first, and the state updated to cover them.
    public mutating func takeNew(from outputs: [CronOutput], now: Date = Date()) -> [CronOutput] {
        guard let watermark else {
            self.watermark = outputs.map(\.modifiedAt).max() ?? now
            seenIDs = Array(outputs.map(\.id).prefix(Self.memory))
            return []
        }
        let seen = Set(seenIDs)
        let fresh = outputs
            .filter { $0.modifiedAt >= watermark && !seen.contains($0.id) }
            .sorted { $0.modifiedAt < $1.modifiedAt }
        guard !fresh.isEmpty else { return [] }
        if let newest = fresh.last?.modifiedAt, newest > watermark {
            self.watermark = newest
        }
        let handled: [String] = fresh.map(\.id).reversed()
        seenIDs = Array((handled + seenIDs).prefix(Self.memory))
        return fresh
    }
}
