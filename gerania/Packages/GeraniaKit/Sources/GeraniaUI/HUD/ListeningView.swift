import SwiftUI

/// The listening state: a small wave that follows the microphone.
public struct ListeningView: View {
    private let model: HUDViewModel

    public init(model: HUDViewModel) {
        self.model = model
    }

    public var body: some View {
        ListeningWaveform(level: model.micLevel)
            .frame(height: 18)
    }
}
