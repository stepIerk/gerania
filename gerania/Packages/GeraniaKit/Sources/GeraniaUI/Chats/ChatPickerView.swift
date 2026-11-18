import GeraniaCore
import HermesKit
import SwiftUI

/// Dropdown with the list of chats.
///
/// The list is grouped into «Сегодня / Вчера / Ранее»; ↑↓ move the highlight, ⏎ opens the
/// chat, ⌘⏎ opens it in the Hermes Desktop.
public struct ChatPickerView: View {
    @Bindable private var input: InputViewModel
    @Bindable private var chats: ChatsModel

    @FocusState private var isSearchFocused: Bool

    public init(input: InputViewModel, chats: ChatsModel) {
        self.input = input
        self.chats = chats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            content
            Divider()
            newChatButton
        }
        .padding(12)
        .onAppear {
            isSearchFocused = true
        }
        .onKeyPress(keys: [.upArrow], phases: .down) { _ in
            chats.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(keys: [.downArrow], phases: .down) { _ in
            chats.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            if press.modifiers.contains(.command) {
                openSelectedInDesktop()
            } else {
                selectHighlighted()
            }
            return .handled
        }
    }

    private var searchField: some View {
        TextField("Поиск чатов", text: $chats.query)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($isSearchFocused)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            }
    }

    @ViewBuilder
    private var content: some View {
        if chats.filteredSessions.isEmpty {
            Text(chats.isLoading ? "Загружаю чаты…" : "Чатов не найдено")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(chats.sections, id: \.kind) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.kind.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                            ForEach(section.sessions, id: \.id) { session in
                                row(for: session)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
    }

    private var newChatButton: some View {
        Button {
            chats.closeList()
            chats.newChat()
            input.startNewChat()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Новый чат")
                    .font(.system(size: 12.5))
                Spacer(minLength: 0)
                Text("⌘N")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }

    private func row(for session: SessionSummary) -> some View {
        Button {
            chats.closeList()
            chats.select(sessionID: session.id)
            input.selectChat(id: session.id, title: session.title)
        } label: {
            ChatRowView(
                session: session,
                isCurrent: session.id == chats.currentSessionID,
                isHighlighted: session.id == highlightedID,
                now: Date()
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if chats.canRename {
                Button("Переименовать…") {
                    input.requestRename(session: session)
                }
            }
        }
    }

    private var highlightedID: String? {
        let sessions = chats.filteredSessions
        guard sessions.indices.contains(chats.selectedIndex) else { return nil }
        return sessions[chats.selectedIndex].id
    }

    private func selectHighlighted() {
        guard let highlightedID else { return }
        chats.closeList()
        chats.select(sessionID: highlightedID)
        guard let session = chats.filteredSessions.first(where: { $0.id == highlightedID }) else { return }
        input.selectChat(id: session.id, title: session.title)
    }

    private func openSelectedInDesktop() {
        guard let highlightedID else { return }
        input.openInDesktop(sessionID: highlightedID)
    }
}
