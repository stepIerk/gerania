import Foundation

/// Terminal application used by «Открыть в Терминале».
public enum TerminalPreference: String, CaseIterable, Sendable, Codable {
    case terminal
    case iTerm

    /// Name shown in the settings.
    public var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm: "iTerm"
        }
    }
}
