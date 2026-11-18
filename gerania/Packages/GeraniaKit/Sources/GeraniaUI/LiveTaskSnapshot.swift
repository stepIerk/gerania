import Foundation
import GeraniaCore

/// Snapshot of one Hermes task started from the live dialog.
struct LiveTaskSnapshot: Identifiable, Sendable, Equatable {
    enum Status: String, Sendable, Equatable {
        case queued
        case running
        case completed
        case failed
        case cancelled

        var isTerminal: Bool {
            self == .completed || self == .failed || self == .cancelled
        }

        var displayName: String {
            switch self {
            case .queued: "в очереди"
            case .running: "выполняется"
            case .completed: "готово"
            case .failed: "ошибка"
            case .cancelled: "отменена"
            }
        }
    }

    let id: String
    let title: String
    let goal: String
    var status: Status
    var summary: String?
    var sessionID: String?

    var json: JSONValue {
        var object: [String: JSONValue] = [
            "task_id": .string(id),
            "title": .string(title),
            "status": .string(status.rawValue),
        ]
        if let summary, !summary.isEmpty {
            object["result"] = .string(String(summary.prefix(4000)))
        }
        if let sessionID {
            object["session_id"] = .string(sessionID)
        }
        return .object(object)
    }
}

enum LiveTaskError: Error, LocalizedError {
    case unknownRequest(String)
    case invalidRequest(String)

    var errorDescription: String? {
        switch self {
        case let .unknownRequest(id):
            "Запрос \(id) не найден"
        case let .invalidRequest(message):
            message
        }
    }
}
