import GeraniaCore
import SwiftUI

/// Card that asks the user to confirm an action of the assistant.
public struct ApprovalView: View {
    private let model: HUDViewModel
    private let request: ServerRequest

    public init(model: HUDViewModel, request: ServerRequest) {
        self.model = model
        self.request = request
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let command = request.command {
                Text(command)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            if let description = request.requestDescription, description != request.command {
                Text(description)
                    .font(HUDTheme.captionFont)
                    .foregroundStyle(HUDTheme.textSecondary)
                    .lineLimit(3)
            }
            HStack(spacing: 6) {
                Button("Разрешить") {
                    answer(.approval(choice: "once"))
                }
                .buttonStyle(HUDPrimaryButtonStyle())
                if supportsAlways {
                    Button("Всегда") {
                        answer(.approval(choice: "always"))
                    }
                    .buttonStyle(HUDSecondaryButtonStyle())
                }
                Button("Отклонить") {
                    answer(.approval(choice: "deny"))
                }
                .buttonStyle(HUDSecondaryButtonStyle())
                Spacer(minLength: 0)
            }
        }
        .onKeyPress(.return) {
            answer(.approval(choice: "once"))
            return .handled
        }
        .onKeyPress(.escape) {
            answer(.approval(choice: "deny"))
            return .handled
        }
    }

    private var supportsAlways: Bool {
        request.choices.contains { choice in
            let normalized = choice.lowercased()
            return normalized.contains("always") || normalized.contains("session")
        }
    }

    private func answer(_ value: ServerRequestAnswer) {
        model.onAction?(.answer(request, value))
    }
}
