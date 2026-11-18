import AppKit
import ApplicationServices
import HermesKit

/// What the machine can do with the Hermes Desktop.
///
/// The checks live in the UI layer, because they need AppKit; the launcher itself stays
/// free of it and only takes the result.
@MainActor
public enum DesktopEnvironment {
    /// Bundle identifiers of the known Hermes Desktop builds.
    public static let bundleIdentifiers = [
        "com.nousresearch.hermes.setup",
        "com.nousresearch.hermes",
    ]

    /// Reads the capabilities of the machine.
    public static func capabilities() -> DesktopLauncher.Capabilities {
        DesktopLauncher.Capabilities(
            isDesktopInstalled: isDesktopInstalled(),
            isDesktopRunning: isDesktopRunning(),
            hasDeepLink: hasDeepLink(),
            isAccessibilityTrusted: AXIsProcessTrusted()
        )
    }

    /// Whether the Desktop application is installed.
    public static func isDesktopInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/Hermes.app")
            || FileManager.default.fileExists(
                atPath: NSHomeDirectory() + "/.hermes/hermes-agent/apps/desktop/release/mac-arm64/Hermes.app"
            )
    }

    /// Whether the Desktop application is running.
    public static func isDesktopRunning() -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.nousresearch.hermes.setup")
        if !running.isEmpty {
            return true
        }
        let releases = NSRunningApplication.runningApplications(withBundleIdentifier: "com.nousresearch.hermes")
        return !releases.isEmpty
    }

    /// Whether the `hermes://` scheme is known to the system.
    public static func hasDeepLink() -> Bool {
        guard let url = URL(string: "\(DesktopLauncher.deepLinkScheme)://open/session/probe") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }

    /// Opens the System Settings page of the accessibility permissions.
    public static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
