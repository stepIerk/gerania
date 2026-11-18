import SwiftUI

/// Metrics of the bottom input panel.
enum InputDesign {
    /// Side of a round action button.
    static let buttonSize: CGFloat = 48
    /// Gap between the field and the round buttons.
    static let spacing: CGFloat = 10
    /// Transparent breathing room around the glass, so shadows are not clipped.
    static let edge: CGFloat = 6
    /// Width of the field for an empty prompt.
    static let baseFieldWidth: CGFloat = 360
    /// The field stops growing here.
    static let maximumFieldWidth: CGFloat = 520
    /// Height of the single-line field.
    static let fieldHeight: CGFloat = 48
    /// Continuous corner radius of the field. Half of the height makes it a capsule.
    static let fieldCorner: CGFloat = 24
    /// Corner radius of the chat picker card.
    static let panelCorner: CGFloat = 20
    /// Gap between the panel and the bottom of the visible screen area.
    static let bottomMargin: CGFloat = 28

    /// Total window width for a given field width.
    static func totalWidth(fieldWidth: CGFloat) -> CGFloat {
        fieldWidth + buttonSize * 4 + spacing * 4 + edge * 2
    }

    /// Initial window height; the field grows upwards from here.
    static var baseHeight: CGFloat {
        fieldHeight + edge * 2
    }
}

/// Applies the system Liquid Glass on macOS 26+, with a material fallback on older systems.
struct InputGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                }
                .overlay {
                    shape.stroke(.white.opacity(0.16), lineWidth: 0.5)
                }
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        let base: Glass = if let tint {
            .regular.tint(tint)
        } else {
            .regular
        }
        return interactive ? base.interactive() : base
    }
}

extension View {
    /// One independent glass element: the field, a button or the chat picker.
    func inputGlass(
        _ shape: some Shape,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(InputGlassSurface(shape: shape, tint: tint, interactive: interactive))
    }
}

/// One render pass for the whole cluster. The container spacing is smaller than the
/// visible gap, so the field and the buttons stay separate at rest.
struct InputGlassGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 4) {
                content
            }
        } else {
            content
        }
    }
}
