import Foundation

/// How Gerania talks to Hermes. `auto` probes Gateway, then ACP, then one-shot.
public enum TransportKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto
    case gateway
    case acp
    case oneshot

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .auto: "Авто"
        case .gateway: "Gateway (WebSocket)"
        case .acp: "ACP (stdio)"
        case .oneshot: "One-shot (hermes -z)"
        }
    }
}
