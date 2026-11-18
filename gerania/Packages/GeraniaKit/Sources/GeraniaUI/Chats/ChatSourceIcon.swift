import Foundation
import HermesKit
import SwiftUI

/// SF Symbol of the client that created the session.
public enum ChatSourceIcon {
    /// Icon for the source of a session.
    public static func symbol(for source: String?) -> String {
        let normalized = (source ?? "").lowercased()
        if normalized.contains("telegram") {
            return "paperplane"
        }
        if normalized.contains("slack") {
            return "bubble.left.and.bubble.right"
        }
        if normalized.contains("discord") {
            return "gamecontroller"
        }
        if normalized.contains("cli") || normalized.contains("tui") {
            return "terminal"
        }
        if normalized.contains("gui") || normalized.contains("desktop") {
            return "macwindow"
        }
        if normalized.contains("acp") {
            return "bolt"
        }
        if normalized.contains("oneshot") {
            return "bolt.fill"
        }
        if normalized.contains("tool") {
            return "wrench.and.screwdriver"
        }
        if normalized.contains("web") {
            return "globe"
        }
        return "bubble.left"
    }
}
