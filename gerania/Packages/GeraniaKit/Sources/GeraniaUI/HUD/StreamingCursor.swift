import SwiftUI

/// Blinking cursor at the end of the streamed answer.
public struct StreamingCursor: View {
    @State private var isVisible = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(HUDTheme.accent)
            .frame(width: 6, height: 13)
            .opacity(reduceMotion ? 0.85 : (isVisible ? 1 : 0.15))
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(530))
                    isVisible.toggle()
                }
            }
    }
}
