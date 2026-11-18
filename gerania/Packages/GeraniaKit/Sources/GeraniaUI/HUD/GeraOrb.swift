import GeraniaCore
import SwiftUI

/// The small status dot that shows what the assistant is doing right now.
///
/// It is the only element of the HUD that moves: a quiet pulse while listening, a slow
/// mesh rotation while thinking and a calm glow while the answer is written. Finished
/// states carry a small glyph, so the state reads even without the title.
public struct GeraOrb: View {
    private let state: GeraState
    private let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: GeraState, level: Float) {
        self.state = state
        self.level = level
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(radialFill)
            if showsMesh {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                    mesh
                        .rotationEffect(.degrees(angle(at: context.date)))
                }
                .clipShape(Circle())
                .opacity(0.5)
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        }
        .frame(width: 18, height: 18)
        .overlay {
            if isListening {
                Circle()
                    .strokeBorder(HUDTheme.accent.opacity(0.32), lineWidth: 1)
                    .scaleEffect(1 + CGFloat(level) * 0.4)
                    .opacity(1 - CGFloat(level) * 0.55)
            }
        }
        .scaleEffect(scale)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: scale)
    }

    private var showsMesh: Bool {
        switch state {
        case .thinking, .streaming: !reduceMotion
        default: false
        }
    }

    private var isListening: Bool {
        if case .listening = state {
            return true
        }
        return false
    }

    /// Small glyph for the settled states; the running ones get the animation instead.
    private var symbol: String? {
        switch state {
        case .done, .speaking: "checkmark"
        case .error: "xmark"
        case .awaitingApproval: "exclamationmark"
        default: nil
        }
    }

    /// The body of the orb: a soft radial light instead of a flat circle.
    private var radialFill: RadialGradient {
        RadialGradient(
            colors: [tint.opacity(0.95), tint.opacity(0.6)],
            center: .center,
            startRadius: 0,
            endRadius: 11
        )
    }

    private var tint: Color {
        switch state {
        case .idle, .done, .speaking: HUDTheme.mutedAccent
        case .listening, .transcribing: HUDTheme.accent
        case .thinking, .streaming: HUDTheme.accent.opacity(0.9)
        case .error: HUDTheme.errorTint.opacity(0.9)
        case .awaitingApproval: Color.orange.opacity(0.9)
        }
    }

    private var mesh: MeshGradient {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0, 0), .init(0.5, 0), .init(1, 0),
                .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                .init(0, 1), .init(0.5, 1), .init(1, 1),
            ],
            colors: meshColors
        )
    }

    private var meshColors: [Color] {
        switch state {
        case .error:
            [
                .red.opacity(0.5), .orange.opacity(0.45), .red.opacity(0.4),
                .orange.opacity(0.35), .red.opacity(0.3), .pink.opacity(0.35),
                .red.opacity(0.3), .orange.opacity(0.25), .red.opacity(0.2),
            ]
        default:
            [
                .purple.opacity(0.6), .indigo.opacity(0.45), .purple.opacity(0.4),
                .indigo.opacity(0.4), .purple.opacity(0.55), .pink.opacity(0.35),
                .purple.opacity(0.4), .indigo.opacity(0.45), .purple.opacity(0.32),
            ]
        }
    }

    private func angle(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate * (isThinking ? 12 : 5)
    }

    private var isThinking: Bool {
        if case .thinking = state {
            return true
        }
        return false
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        switch state {
        case .listening:
            return 1 + CGFloat(level) * 0.1
        case .thinking:
            return 1 + 0.03 * CGFloat(sin(Date().timeIntervalSinceReferenceDate * 1.4))
        default:
            return 1
        }
    }
}
