import Foundation

public enum LiveError: Error, LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case invalidEndpoint
    case unauthorized
    case quotaExceeded
    case network(String)
    case timeout
    case protocolError(String)
    case audio(String)
    case sessionClosed(String)
    case cancelled

    public init(serverMessage: String) {
        let lower = serverMessage.lowercased()
        if lower.contains("api key")
            || lower.contains("unauthenticated")
            || lower.contains("permission denied")
        {
            self = .unauthorized
        } else if lower.contains("quota") || lower.contains("rate limit") {
            self = .quotaExceeded
        } else {
            self = .protocolError(serverMessage)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Не задан ключ Gemini API"
        case .invalidEndpoint:
            "Некорректный адрес Gemini Live"
        case .unauthorized:
            "Gemini отклонил ключ API"
        case .quotaExceeded:
            "Закончилась квота Gemini Live"
        case let .network(message):
            "Сеть недоступна: \(message)"
        case .timeout:
            "Gemini Live не ответил вовремя"
        case let .protocolError(message):
            "Ошибка протокола Gemini Live: \(message)"
        case let .audio(message):
            "Ошибка звука: \(message)"
        case let .sessionClosed(message):
            "Сессия Gemini Live закрыта: \(message)"
        case .cancelled:
            "Сессия Gemini Live отменена"
        }
    }
}
