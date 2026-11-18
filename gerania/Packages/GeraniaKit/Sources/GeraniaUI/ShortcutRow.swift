import KeyboardShortcuts
import SwiftUI

/// Row of the settings with a shortcut recorder and a warning for reserved combinations.
public struct ShortcutRow: View {
    private let title: String
    private let name: KeyboardShortcuts.Name

    @State private var conflict: String?

    public init(_ title: String, name: KeyboardShortcuts.Name) {
        self.title = title
        self.name = name
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            KeyboardShortcuts.Recorder(title, name: name) { shortcut in
                conflict = Self.conflictName(for: shortcut)
            }
            if let conflict {
                Label(
                    "\(conflict) — сочетание занято системой, выберите другое",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            }
        }
        .onAppear {
            conflict = Self.conflictName(for: KeyboardShortcuts.getShortcut(for: name))
        }
    }

    @MainActor
    private static func conflictName(for shortcut: KeyboardShortcuts.Shortcut?) -> String? {
        guard let conflict = SystemShortcutConflict.conflict(for: shortcut) else { return nil }
        return SystemShortcutConflict.describe(conflict)
    }
}
