import SwiftUI

/// Accent-filled button of the HUD.
///
/// The HUD is a non-activating panel, so the system button styles render it as an
/// inactive window and turn the accent into grey. These styles paint the accent
/// themselves, so the primary action stays recognisable in a passive panel.
struct HUDPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: HUDTheme.controlRadius, style: .continuous)
                    .fill(HUDTheme.accent.opacity(configuration.isPressed ? 0.78 : 1))
            }
            .contentShape(Rectangle())
    }
}

/// Quiet button of the HUD with a real fill and a hairline.
struct HUDSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: HUDTheme.controlRadius, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.primary.opacity(0.1)
                            : HUDTheme.controlFill
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: HUDTheme.controlRadius, style: .continuous)
                    .strokeBorder(HUDTheme.controlBorder, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
    }
}
