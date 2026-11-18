import SwiftUI

/// Black surface of the HUD, shaped as an extension of the MacBook notch.
///
/// The panel is deliberately opaque: it must blend with the hardware cutout and stay
/// readable over any window. The only decoration is a thin border, which turns into a
/// slow violet highlight while the model is thinking.
public struct NotchCard<Content: View>: View {
    private let isRunning: Bool
    private let isComputerUse: Bool
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isRunning: Bool, isComputerUse: Bool = false, @ViewBuilder content: () -> Content) {
        self.isRunning = isRunning
        self.isComputerUse = isComputerUse
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, HUDTheme.notchPadding)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background {
                shape.fill(Color.black)
            }
            .clipShape(shape)
            .overlay {
                border
            }
            .environment(\.colorScheme, .dark)
    }

    private var shape: NotchShape {
        NotchShape(topCornerRadius: 8, bottomCornerRadius: 18)
    }

    /// The outline without its top edge: the panel is flush with the screen edge, so a
    /// stroke there would be clipped away.
    private var outline: NotchBorder {
        NotchBorder(topCornerRadius: 8, bottomCornerRadius: 18, inset: 1)
    }

    @ViewBuilder
    private var border: some View {
        if isComputerUse {
            // Driving the computer outranks the thinking glow: the frame stays
            // amber so the control state is visible at a glance.
            ZStack {
                outline.stroke(HUDTheme.computerTint.opacity(0.35), lineWidth: 1)
                outline.stroke(HUDTheme.computerTint.opacity(0.75), lineWidth: 2)
            }
        } else if isRunning {
            if reduceMotion {
                ZStack {
                    outline.stroke(HUDTheme.accent.opacity(0.28), lineWidth: 1)
                    outline.stroke(HUDTheme.accent.opacity(0.55), lineWidth: 2)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    ZStack {
                        outline.stroke(HUDTheme.accent.opacity(0.28), lineWidth: 1)
                        outline.stroke(
                            glow(at: context.date),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                    }
                }
            }
        } else {
            shape.stroke(HUDTheme.hairline, lineWidth: 0.5)
        }
    }

    /// A violet highlight that travels around the silhouette.
    private func glow(at date: Date) -> AngularGradient {
        let period: TimeInterval = 3.2
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return AngularGradient(
            gradient: Gradient(colors: [
                HUDTheme.accent.opacity(0),
                HUDTheme.accent.opacity(0.9),
                HUDTheme.accent.opacity(0.2),
                HUDTheme.accent.opacity(0),
            ]),
            center: .center,
            angle: .degrees(phase * 360)
        )
    }
}
