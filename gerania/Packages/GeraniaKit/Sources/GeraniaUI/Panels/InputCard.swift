import SwiftUI

/// Root of the bottom input panel.
///
/// The window is transparent and the glass lives in the row itself, so this card only
/// adds breathing room, measures the height and plays the bottom spring reveal.
struct InputCard: View {
    private let model: InputViewModel
    private let chats: ChatsModel

    init(model: InputViewModel, chats: ChatsModel) {
        self.model = model
        self.chats = chats
    }

    var body: some View {
        InputView(model: model, chats: chats)
            .padding(InputDesign.edge)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                model.onHeightChange?(height)
            }
            .scaleEffect(model.isVisible ? 1 : 0.96, anchor: .bottom)
            .offset(y: model.isVisible ? 0 : 14)
            .opacity(model.isVisible ? 1 : 0)
            .allowsHitTesting(model.isVisible)
    }
}
