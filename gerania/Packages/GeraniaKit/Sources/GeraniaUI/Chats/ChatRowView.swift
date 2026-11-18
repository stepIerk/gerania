import GeraniaCore
import HermesKit
import SwiftUI

/// One row of the chat list.
public struct ChatRowView: View {
    private let session: SessionSummary
    private let isCurrent: Bool
    private let isHighlighted: Bool
    private let now: Date

    public init(session: SessionSummary, isCurrent: Bool, isHighlighted: Bool, now: Date) {
        self.session = session
        self.isCurrent = isCurrent
        self.isHighlighted = isHighlighted
        self.now = now
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ChatSourceIcon.symbol(for: session.source))
                .font(.system(size: 11))
                .foregroundStyle(isCurrent ? HUDTheme.accent : Color.secondary)
                .frame(width: 14, height: 14)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(RelativeTime.string(for: date, now: now))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                if !session.preview.isEmpty {
                    Text(session.preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHighlighted ? HUDTheme.accent.opacity(0.16) : Color.clear)
        }
        .contentShape(Rectangle())
    }

    private var title: String {
        let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? session.id : trimmed
    }

    private var date: Date {
        session.updatedAt ?? session.startedAt ?? now
    }
}
