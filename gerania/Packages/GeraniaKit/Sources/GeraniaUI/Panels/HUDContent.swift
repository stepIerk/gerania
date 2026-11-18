import SwiftUI

/// Root view of the HUD panel.
///
/// The black silhouette grows out of the notch with a spring, and the window is ordered
/// out only after the collapse animation has finished.
public struct HUDContent: View {
    private let model: HUDViewModel

    public init(model: HUDViewModel) {
        self.model = model
    }

    public var body: some View {
        ZStack(alignment: .top) {
            if model.isVisible {
                NotchCard(isRunning: isRunning, isComputerUse: model.isComputerUseActive) {
                    HUDView(model: model)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    model.reportHeight(height)
                }
                .onHover { hovering in
                    model.onHover?(hovering)
                }
                .transition(.notchDrop)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }

    private var isRunning: Bool {
        if case .thinking = model.state {
            return true
        }
        return false
    }
}
