import SwiftUI

/// Reveals a panel out of the notch: a mask grows from a thin line at the top centre
/// and widens to the full card, so the black silhouette looks like it is unrolling
/// from the camera housing instead of fading in.
///
/// The modifier is public because the mini window reuses it: there the card keeps its
/// size and only the mask moves, so the window does not jump.
public struct NotchReveal: ViewModifier, Animatable {
    /// 0 — the panel is folded into the notch, 1 — it is fully shown.
    public var progress: CGFloat

    public init(progress: CGFloat) {
        self.progress = progress
    }

    public nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    public func body(content: Content) -> some View {
        content
            .mask(alignment: .top) {
                Rectangle()
                    .scaleEffect(x: 0.5 + 0.5 * progress, y: progress, anchor: .top)
            }
            .opacity(Double(min(max(progress * 2, 0), 1)))
    }
}

public extension AnyTransition {
    /// Spring-driven appearance and disappearance for the notch panels.
    static var notchDrop: AnyTransition {
        .modifier(
            active: NotchReveal(progress: 0),
            identity: NotchReveal(progress: 1)
        )
    }
}
