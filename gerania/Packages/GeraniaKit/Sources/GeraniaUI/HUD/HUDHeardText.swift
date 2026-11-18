import SwiftUI

/// The recognized command, revealed letter by letter.
public struct HUDHeardText: View {
    private let text: String
    private let duration: TimeInterval

    @State private var shown = ""

    public init(text: String, duration: TimeInterval = 0.25) {
        self.text = text
        self.duration = duration
    }

    public var body: some View {
        Text(shown)
            .font(HUDTheme.captionFont)
            .foregroundStyle(HUDTheme.textSecondary)
            .lineLimit(2)
            // Two lines are reserved from the first character: otherwise every
            // wrap grows the card, and the panel resizes while SwiftUI is laying
            // it out. That re-entered the window constraint pass and crashed.
            .frame(minHeight: 30, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: text) {
                await reveal()
            }
    }

    private func reveal() async {
        // Partial hypotheses usually extend the previous one: continue from the
        // visible prefix instead of blinking back to an empty line.
        if !text.hasPrefix(shown) {
            shown = ""
        }
        guard shown.count < text.count else { return }
        let remainder = text.dropFirst(shown.count)
        let steps = max(1, min(24, remainder.count))
        let step = max(1, remainder.count / steps)
        let pause = UInt64(duration / Double(steps) * 1_000_000)
        var index = text.index(text.startIndex, offsetBy: shown.count)
        while index < text.endIndex {
            let next = text.index(index, offsetBy: step, limitedBy: text.endIndex) ?? text.endIndex
            shown = String(text[..<next])
            index = next
            try? await Task.sleep(for: .microseconds(Int(pause)))
        }
        shown = text
    }
}
