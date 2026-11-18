import Foundation

/// What Gerania does when Hermes asks for a dangerous-command approval.
public enum ApprovalPolicy: String, CaseIterable, Codable, Sendable, Identifiable {
    case ask
    case denyInVoice

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .ask: "Спрашивать"
        case .denyInVoice: "Запрещать в голосовом режиме"
        }
    }
}
