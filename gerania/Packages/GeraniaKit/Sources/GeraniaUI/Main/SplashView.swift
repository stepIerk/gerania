import SwiftUI

/// The animation of the flower on a black background.
///
/// The animation is played once, from the first frame to the last, and only then the
/// window of the application shows the settings.
struct SplashView: View {
    private let animation: SplashAnimation
    private let onFinished: () -> Void

    @State private var frameIndex = 0

    init(animation: SplashAnimation, onFinished: @escaping () -> Void) {
        self.animation = animation
        self.onFinished = onFinished
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                image
                    .frame(width: size(for: proxy.size).width, height: size(for: proxy.size).height)
            }
        }
        .task { await play() }
    }

    private var image: some View {
        Image(nsImage: current)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    private var current: NSImage {
        animation.frames[min(frameIndex, animation.frames.count - 1)].image
    }

    /// The frame is shown bigger than its own size, but not bigger than the window.
    private func size(for available: CGSize) -> CGSize {
        let natural = animation.size
        guard natural.width > 0, natural.height > 0 else { return .zero }
        let scale = min(
            available.width * 0.7 / natural.width,
            available.height * 0.7 / natural.height,
            2
        )
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    /// Plays the frames one by one and reports the end.
    private func play() async {
        for index in animation.frames.indices {
            frameIndex = index
            let duration = animation.frames[index].duration
            try? await Task.sleep(for: .seconds(duration))
        }
        onFinished()
    }
}
