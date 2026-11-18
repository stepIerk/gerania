import GeraniaCore
import SwiftUI

/// Visual tokens of the Gerania panels.
///
/// The panels are solid black, like the MacBook notch. Hierarchy comes from type weight
/// and spacing; the violet accent is reserved for the few actions that matter.
public enum HUDTheme {
    /// Width of the compact HUD.
    public static let width: CGFloat = 420
    /// Inner padding of a rounded panel.
    public static let padding: CGFloat = 12
    /// Horizontal padding of the notch HUD.
    public static let notchPadding: CGFloat = 14
    /// Corner radius of a rounded panel.
    public static let panelRadius: CGFloat = 16
    /// Smallest height of the HUD, so a short state stays a compact strip.
    public static let minHeight: CGFloat = 44
    /// Width of the text column inside the notch.
    public static var contentWidth: CGFloat {
        width - notchPadding * 2
    }

    /// Title of the state.
    public static let titleFont = Font.system(size: 12.5, weight: .semibold)
    /// Body text of the answer.
    public static let bodyFont = Font.system(size: 13)
    /// Secondary body text.
    public static let captionFont = Font.system(size: 11)
    /// Monospaced text and code.
    public static let codeFont = Font.system(size: 12, design: .monospaced)

    /// Primary text on black.
    public static let textPrimary = Color.white
    /// Secondary text on black.
    public static let textSecondary = Color.white.opacity(0.58)
    /// Hairline between black surfaces.
    public static let hairline = Color.white.opacity(0.11)

    /// Radius of the small controls inside the panels.
    public static let controlRadius: CGFloat = 8
    /// Fill of the small controls (chips, buttons, the field).
    public static let controlFill = Color.white.opacity(0.075)
    /// Border of the small controls.
    public static let controlBorder = Color.white.opacity(0.11)

    /// Accent of the active state: Gerania's violet.
    public static let accent = Color(red: 0.545, green: 0.361, blue: 0.965)
    /// Muted accent used for the quiet states.
    public static let mutedAccent = Color.white.opacity(0.3)
    /// Tint of the error state.
    public static let errorTint = Color.red
    /// Tint of the «Gerania drives the computer» state.
    public static let computerTint = Color(red: 1.0, green: 0.66, blue: 0.26)
}
