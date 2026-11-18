import GeraniaCore
import HermesKit
import SwiftUI

/// Table of all sessions of the user.
///
/// A double click makes the session current.
public struct ChatsSettingsView: View {
    @Bindable private var chats: ChatsModel

    public init(chats: ChatsModel) {
        self.chats = chats
    }

    public var body: some View {
        Group {
            if chats.sessions.isEmpty {
                VStack(spacing: 6) {
                    Text("Чатов пока нет")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Обновить") {
                        Task { await chats.refresh() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                        ForEach(chats.sessions, id: \.id) { session in
                            row(for: session)
                        }
                    }
                }
            }
        }
        .task {
            await chats.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Чат")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Источник")
                .frame(width: 90, alignment: .leading)
            Text("Обновлён")
                .frame(width: 90, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func row(for session: SessionSummary) -> some View {
        let isCurrent = session.id == chats.currentSessionID
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: ChatSourceIcon.symbol(for: session.source))
                    .font(.system(size: 11))
                    .foregroundStyle(isCurrent ? HUDTheme.accent : Color.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title.isEmpty ? session.id : session.title)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .lineLimit(1)
                    if !session.preview.isEmpty {
                        Text(session.preview)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(session.source.isEmpty ? "—" : session.source)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(RelativeTime.string(for: session.updatedAt ?? session.startedAt ?? Date(), now: Date()))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(HUDTheme.accent.opacity(0.12))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            chats.select(sessionID: session.id)
        }
        .help("Двойной клик — сделать текущим")
    }
}
