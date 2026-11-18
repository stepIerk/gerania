import Foundation
import GeraniaCore

/// Why a model is temporarily skipped by the router.
public enum ModelHealthIssue: String, Sendable, Equatable {
    /// The provider says the quota, rate limit or plan is exhausted.
    case quota
    /// The provider rejected the key: wrong, expired or missing.
    case auth
    /// The provider does not have this model.
    case missing

    /// Short Russian word for the HUD and the settings.
    public var title: String {
        switch self {
        case .quota: "лимит"
        case .auth: "ключ"
        case .missing: "нет модели"
        }
    }

    /// How long the router avoids the model after such a failure.
    public var cooldown: TimeInterval {
        switch self {
        case .quota: 10 * 60
        case .auth: 24 * 60 * 60
        case .missing: 30 * 60
        }
    }
}

/// A cooldown record of one model.
public struct ModelHealthRecord: Sendable, Equatable {
    public let issue: ModelHealthIssue
    public let until: Date

    public init(issue: ModelHealthIssue, until: Date) {
        self.issue = issue
        self.until = until
    }
}

/// Remembers which models failed recently.
///
/// The router tries the healthy candidates first and the cooling ones last: a
/// model whose quota is over is unlikely to answer a minute later, while a
/// missing key stays broken until the user fixes it. The store is deliberately
/// in memory only: after a restart the user probably changed the keys.
public actor ModelHealthStore {
    private var records: [String: ModelHealthRecord] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// The active cooldown of the candidate, if any.
    public func record(for candidate: ModelCandidate) -> ModelHealthRecord? {
        guard let record = records[candidate.id] else { return nil }
        guard record.until > now() else {
            records[candidate.id] = nil
            return nil
        }
        return record
    }

    public func isCoolingDown(_ candidate: ModelCandidate) -> Bool {
        record(for: candidate) != nil
    }

    /// Classifies the error and starts the cooldown. Ordinary errors return nil.
    @discardableResult
    public func markFailure(_ candidate: ModelCandidate, error: HermesError) -> ModelHealthRecord? {
        guard let issue = Self.issue(for: error) else { return nil }
        let record = ModelHealthRecord(issue: issue, until: now().addingTimeInterval(issue.cooldown))
        records[candidate.id] = record
        return record
    }

    /// The model answered: forget its failures.
    public func markHealthy(_ candidate: ModelCandidate) {
        records[candidate.id] = nil
    }

    public func clearAll() {
        records.removeAll()
    }

    /// Which cooldown the error deserves; nil when another model would not help.
    public nonisolated static func issue(for error: HermesError) -> ModelHealthIssue? {
        if error.isAuthFailure {
            return .auth
        }
        if error.isModelMissing {
            return .missing
        }
        if error.isModelUnavailable {
            return .quota
        }
        return nil
    }
}
