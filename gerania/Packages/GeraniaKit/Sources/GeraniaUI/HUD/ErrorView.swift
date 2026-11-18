import SwiftUI

/// Short error message with the details behind it and a retry button.
public struct ErrorView: View {
    private let model: HUDViewModel
    private let message: String

    public init(model: HUDViewModel, message: String) {
        self.model = model
        self.message = message
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(HUDTheme.bodyFont)
                .foregroundStyle(HUDTheme.textPrimary)
                .lineLimit(3)
                .textSelection(.enabled)

            if model.showsErrorDetails, let details = model.errorDetails, !details.isEmpty {
                ScrollView {
                    Text(details)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
                .padding(7)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(HUDTheme.controlFill)
                }
                .transition(.opacity)
            }

            HStack(spacing: 8) {
                if model.errorDetails != nil {
                    Button(model.showsErrorDetails ? "Скрыть детали" : "Детали") {
                        withAnimation(.easeOut(duration: 0.16)) {
                            model.showsErrorDetails.toggle()
                        }
                    }
                    .buttonStyle(HUDSecondaryButtonStyle())
                }
                Spacer(minLength: 0)
                Button("Повторить") {
                    model.onAction?(.retry)
                }
                .buttonStyle(HUDPrimaryButtonStyle())
            }
        }
    }
}
