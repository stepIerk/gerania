import SwiftUI

/// Twenty-four bars that follow the microphone level.
///
/// The view is stateless: the level arrives already smoothed, the bars are drawn from the
/// level and the clock, so there is no state churn between the frames.
public struct ListeningWaveform: View {
    private let level: Float

    public init(level: Float) {
        self.level = level
    }

    public var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let step = size.width / CGFloat(Self.barCount)
                let width = max(2, step - 3)
                for index in 0 ..< Self.barCount {
                    let wave = 0.55 + 0.45 * sin(time * 3.4 + Double(index) * 0.55)
                    let value = 0.12 + CGFloat(level) * 0.88 * CGFloat(wave)
                    let height = max(3, size.height * value)
                    let rect = CGRect(
                        x: CGFloat(index) * step + 1.5,
                        y: (size.height - height) / 2,
                        width: width,
                        height: height
                    )
                    canvas.fill(
                        Path(roundedRect: rect, cornerRadius: width / 2),
                        with: .color(HUDTheme.accent.opacity(0.75))
                    )
                }
            }
        }
        .frame(height: 26)
    }

    private static let barCount = 24
}
