import Foundation

/// Where the floating HUD panel is anchored.
public enum PanelPosition: String, CaseIterable, Codable, Sendable, Identifiable {
    case notch
    case topRight
    case belowMenuBarIcon

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .notch: "У выреза"
        case .topRight: "Справа сверху"
        case .belowMenuBarIcon: "Под иконкой меню-бара"
        }
    }
}
