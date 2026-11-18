import Foundation
import GeraniaCore

public typealias SessionID = String

public struct SessionSummary: Identifiable, Sendable, Equatable {
    public let id: SessionID
    public let title: String
    public let preview: String
    public let updatedAt: Date?
    public let source: String
    public let cwd: String?
    public let startedAt: Date?
    public let messageCount: Int
    public let isRunning: Bool

    public init(
        id: SessionID,
        title: String,
        preview: String = "",
        updatedAt: Date? = nil,
        source: String = "",
        cwd: String? = nil,
        startedAt: Date? = nil,
        messageCount: Int = 0,
        isRunning: Bool = false
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.updatedAt = updatedAt
        self.source = source
        self.cwd = cwd
        self.startedAt = startedAt
        self.messageCount = messageCount
        self.isRunning = isRunning
    }
}

public enum PromptMode: Sendable, Equatable {
    case voice
    case text
}

public enum HermesEvent: Sendable, Equatable {
    case sessionBound(SessionID)
    case thinkingStarted
    case reasoningDelta(String)
    case textDelta(String)
    case toolStarted(id: String, name: String, detail: String?)
    /// What the finished tool returned: a local screenshot and a short summary.
    case toolOutput(id: String, imagePath: String?, summary: String?)
    case toolFinished(id: String, ok: Bool)
    case serverRequest(ServerRequest)
    case completed(finalText: String?)
    case cancelled
    case failed(HermesError)
}

public enum HermesError: Error, LocalizedError, Sendable, Equatable {
    case binaryNotFound
    case notConfigured(String)
    case transportUnavailable(TransportKind)
    case connectionFailed(String)
    case protocolError(String)
    case timeout(String)
    case processFailed(exitCode: Int32, message: String)

    /// The model cannot serve the request: the quota is over, the provider refused
    /// or the limit of the plan is reached. Such an error is worth retrying with
    /// another model.
    public var isModelUnavailable: Bool {
        matches(Self.modelUnavailableMarkers)
    }

    /// The provider rejected the credentials: there is no key, it is wrong or expired.
    public var isAuthFailure: Bool {
        matches(Self.authFailureMarkers)
    }

    /// The provider does not know such a model, or it was removed.
    public var isModelMissing: Bool {
        matches(Self.modelMissingMarkers)
    }

    private func matches(_ markers: [String]) -> Bool {
        guard let reason = failureText?.lowercased() else { return false }
        return markers.contains { reason.contains($0) }
    }

    private var failureText: String? {
        switch self {
        case let .protocolError(detail),
             let .connectionFailed(detail),
             let .notConfigured(detail):
            detail
        case let .processFailed(_, message):
            message
        default:
            nil
        }
    }

    /// Markers of an exhausted quota or a refused plan.
    static let modelUnavailableMarkers = [
        "permission_denied", "permission denied",
        "insufficient_quota", "quota", "rate limit", "rate_limit", "ratelimit",
        "resource_exhausted", "resource exhausted", "429",
        "billing", "credit", "payment required", "top up your credits",
        "exceeded your current quota", "budget limit exceeded", "spending limit",
        "usage limit", "no usable credits", "plan does not include",
        "account is deactivated", "out of funds", "out of credits",
        "model_not_supported_on_free_tier", "not available on the free tier",
        "free tier",
    ]

    /// Markers of a missing, wrong or expired key.
    static let authFailureMarkers = [
        "401", "unauthorized", "invalid api key", "invalid_api_key",
        "api key not valid", "api_key_invalid", "incorrect api key",
        "missing api key", "no api key", "authentication", "not authenticated",
        "invalid auth", "auth failed", "credentials",
    ]

    /// Markers of a model the provider does not have.
    static let modelMissingMarkers = [
        "model_not_found", "model not found", "unknown model", "no such model",
        "invalid model", "model does not exist", "model is not supported",
        "not a valid model", "404",
    ]

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            "Не найден hermes. Укажите путь в настройках или установите Hermes Agent."
        case let .notConfigured(detail):
            "Hermes не настроен: \(detail)"
        case let .transportUnavailable(kind):
            "Транспорт \(kind.displayName) недоступен."
        case let .connectionFailed(reason):
            "Не удалось подключиться к Hermes: \(reason)"
        case let .protocolError(reason):
            "Ошибка протокола Hermes: \(reason)"
        case let .timeout(operation):
            "Hermes не ответил вовремя: \(operation)."
        case let .processFailed(exitCode, message):
            "Hermes завершился с кодом \(exitCode): \(message)"
        }
    }
}
