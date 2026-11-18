import AppKit

/// Deep links into System Settings, so the person does not search for a toggle.
enum SystemSettingsLink {
    /// `service` is a pane anchor such as `Privacy_Microphone`.
    @MainActor
    static func openPrivacy(_ service: String) {
        let link = "x-apple.systempreferences:com.apple.preference.security?\(service)"
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
